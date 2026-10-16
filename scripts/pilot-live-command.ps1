$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$expectedRun='38930283997'
$expectedVm=[guid]'66b514d0-7246-493f-ade3-1f004cd12411'
if($env:COMPUTERNAME -ine 'runnervm0xl3a'){throw 'Unexpected host; refusing diagnostic read.'}
$control=Join-Path $env:ProgramData ('WindowsHomePilot\'+$expectedRun)
$session=[IO.File]::ReadAllText((Join-Path $control 'session.json'))|ConvertFrom-Json
if($session.runId -cne $expectedRun -or [guid]$session.vmId -ne $expectedVm){throw 'Live pilot identity mismatch.'}
$records=@()
foreach($sub in @('requests','responses')){
 foreach($file in [IO.Directory]::GetFiles((Join-Path $control $sub))){
  $stream=$null
  try{
   $stream=[IO.File]::Open($file,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
   $length=$stream.Length
   $start=[Math]::Max(0,$length-32768)
   [void]$stream.Seek($start,[IO.SeekOrigin]::Begin)
   $buffer=New-Object byte[] ([int]($length-$start))
   $count=$stream.Read($buffer,0,$buffer.Length)
   $records+=[pscustomobject]@{folder=$sub;name=[IO.Path]::GetFileName($file);length=$length;tail=[Text.Encoding]::UTF8.GetString($buffer,0,$count)}
  }catch{$records+=[pscustomobject]@{folder=$sub;name=[IO.Path]::GetFileName($file);error=$_.Exception.GetType().Name}}
  finally{if($stream){$stream.Dispose()}}
 }
}
[ordered]@{host=$env:COMPUTERNAME;run=$session.runId;vmId=$session.vmId;generation=$session.generation;files=$records;utc=[DateTime]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 6 -Compress
