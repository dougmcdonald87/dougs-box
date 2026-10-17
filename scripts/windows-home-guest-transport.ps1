# Data-only guest -> host transport. Existing operator worker owns request validation.
function Add-WindowsHomeGuestRequest {
 [CmdletBinding()]
 param([Parameter(Mandatory)][string]$ControlDir,
       [Parameter(Mandatory)][string]$Name,
       [Parameter(Mandatory)][string]$Json)
 if($Name -cnotmatch '^request-[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}\.json$' -or
    [Text.Encoding]::UTF8.GetByteCount($Json) -gt 4096){return $false}
 try {$null=ConvertFrom-Json -InputObject $Json -ErrorAction Stop} catch {return $false}
 $requests=Join-Path $ControlDir 'requests';$responses=Join-Path $ControlDir 'responses'
 foreach($directory in @($ControlDir,$requests,$responses)){
  $item=Get-Item -LiteralPath $directory -Force -ErrorAction Stop
  if(-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Guest transport directory is unsafe.'}
 }
 $dest=Join-Path $requests $Name
 $receipt=Join-Path $responses ($Name.Replace('request-','response-'))
 foreach($existing in @($dest,($dest+'.working'),$receipt)){
  if(Test-Path -LiteralPath $existing){
   $item=Get-Item -LiteralPath $existing -Force -ErrorAction Stop
   if($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Guest transport destination is unsafe.'}
   return $true
  }
 }
 $temp=Join-Path $requests ('.guest-'+[guid]::NewGuid().ToString('D')+'.tmp')
 try {
  $stream=[IO.File]::Open($temp,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
  try {$bytes=[Text.UTF8Encoding]::new($false).GetBytes($Json);$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)} finally {$stream.Dispose()}
  # Move without overwrite: a repeated batch may acknowledge, never replace, an operation.
  try {[IO.File]::Move($temp,$dest)} catch {
   if(-not(Test-Path -LiteralPath $dest)){throw}
  }
  return $true
 } finally {if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Force -ErrorAction Stop}}
}

# Receipt polling is independent of guest request files, which are acknowledged early.
function Get-WindowsHomeGuestReceiptBatch {
 [CmdletBinding()]
 param([Parameter(Mandatory)][string]$ControlDir,[ValidateRange(0,2147483647)][int]$Offset=0)
 $responses=Join-Path $ControlDir 'responses'
 $directory=Get-Item -LiteralPath $responses -Force -ErrorAction Stop
 if(-not $directory.PSIsContainer -or ($directory.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Receipt directory is unsafe.'}
 $files=@(Get-ChildItem -LiteralPath $responses -File -Force -ErrorAction Stop|
  Where-Object {$_.Name -cmatch '^response-[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}\.json$'}|Sort-Object Name|Select-Object -Skip $Offset -First 32)
 foreach($file in $files){
  if(($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $file.Length -gt 4096){continue}
  $json=[IO.File]::ReadAllText($file.FullName)
  if([Text.Encoding]::UTF8.GetByteCount($json) -gt 4096){continue}
  try {$null=ConvertFrom-Json $json -ErrorAction Stop} catch {continue}
  [pscustomobject]@{name=$file.Name;json=$json}
 }
}

# These two self-contained functions also execute INSIDE the guest over PSDirect.
function Get-WindowsHomeGuestRequestBatch {
 param([Parameter(Mandatory)][string]$GuestControlDir)
 $ErrorActionPreference='Stop'
 $directory=Join-Path $GuestControlDir 'requests'
 foreach($p in @($GuestControlDir,$directory)){
  $item=Get-Item -LiteralPath $p -Force
  if(-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Guest request directory is unsafe.'}
 }
 $files=@(Get-ChildItem -LiteralPath $directory -File -Force|
  Where-Object {$_.Name -cmatch '^request-[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}\.json$'}|Sort-Object Name)
 $emitted=0
 foreach($file in $files){
  if(($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $file.Length -gt 4096){continue}
  $stream=[IO.File]::OpenRead($file.FullName)
  try {
   $bytes=New-Object byte[] 4097;$count=0
   while($count -lt $bytes.Length){$read=$stream.Read($bytes,$count,($bytes.Length-$count));if($read -eq 0){break};$count+=$read}
  } finally {$stream.Dispose()}
  if($count -gt 4096){continue}
  $payload=New-Object byte[] $count;[Array]::Copy($bytes,$payload,$count)
  $hash=[Security.Cryptography.SHA256]::Create()
  try {$digest=([BitConverter]::ToString($hash.ComputeHash($payload))).Replace('-','')} finally {$hash.Dispose()}
  try {$json=[Text.UTF8Encoding]::new($false,$true).GetString($payload);$null=ConvertFrom-Json $json -ErrorAction Stop} catch {continue}
  [pscustomobject]@{name=$file.Name;json=$json;sha256=$digest}
  $emitted++;if($emitted -ge 32){break}
 }
}

function Complete-WindowsHomeGuestControlBatch {
 param([Parameter(Mandatory)][string]$GuestControlDir,[object[]]$Acknowledged=@(),[object[]]$Receipts=@())
 $ErrorActionPreference='Stop'
 foreach($p in @($GuestControlDir,(Join-Path $GuestControlDir 'requests'),(Join-Path $GuestControlDir 'responses'))){
  $item=Get-Item -LiteralPath $p -Force
  if(-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Guest control directory is unsafe.'}
 }
 foreach($ack in @($Acknowledged|Select-Object -First 32)){
  if($ack.name -cnotmatch '^request-[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}\.json$' -or $ack.sha256 -cnotmatch '^[0-9A-F]{64}$'){continue}
  $path=Join-Path (Join-Path $GuestControlDir 'requests') $ack.name
  if(-not(Test-Path -LiteralPath $path)){continue}
  $file=Get-Item -LiteralPath $path -Force
  if($file.PSIsContainer -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $file.Length -gt 4096){continue}
  if((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ceq $ack.sha256){Remove-Item -LiteralPath $path -Force}
 }
 foreach($receipt in @($Receipts|Select-Object -First 32)){
  if($receipt.name -cnotmatch '^response-[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}\.json$' -or [Text.Encoding]::UTF8.GetByteCount([string]$receipt.json) -gt 4096){continue}
  $dest=Join-Path (Join-Path $GuestControlDir 'responses') $receipt.name
  if(Test-Path -LiteralPath $dest){$item=Get-Item -LiteralPath $dest -Force;if($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Guest receipt destination is unsafe.'}}
  $temp=Join-Path (Join-Path $GuestControlDir 'responses') ('.receipt-'+[guid]::NewGuid()+'.tmp')
  try {
   [IO.File]::WriteAllText($temp,[string]$receipt.json,[Text.UTF8Encoding]::new($false))
   if(Test-Path -LiteralPath $dest){[IO.File]::Replace($temp,$dest,[NullString]::Value)}else{[IO.File]::Move($temp,$dest)}
  } finally {if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Force}}
 }
}
