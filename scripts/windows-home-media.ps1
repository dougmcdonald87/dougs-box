# Official, hash-checked media downloader for the owned Windows Home probe.
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'windows-state-probe.ps1')
function Test-WindowsHomeMediaRequest {
    param([Parameter(Mandatory)][string]$Uri,
          [Parameter(Mandatory)][string]$Sha256,
          [Parameter(Mandatory)][string]$Root,
          [Parameter(Mandatory)][string]$VmName)
    $reason='';$address=$null
    $facts=@{FreeBytes=100GB;AvailableMemoryBytes=12GB;HyperVReady=$true;ExistingVm=$false;RootOccupied=$false}
    $policy=Test-WindowsStateProbePolicy -Root $Root -VmName $VmName -Facts $facts
    if(-not $policy.eligible){$reason=$policy.reason}
    elseif(-not [uri]::TryCreate($Uri,[UriKind]::Absolute,[ref]$address)){$reason='Invalid media URL.'}
    elseif($address.Scheme -cne 'https' -or $address.DnsSafeHost -ine 'software.download.prss.microsoft.com' -or $address.UserInfo){$reason='Official Microsoft HTTPS media origin required.'}
    elseif($Sha256 -cnotmatch '^[0-9a-fA-F]{64}$'){$reason='Published SHA256 required.'}
    [pscustomobject]@{accepted=([string]::IsNullOrEmpty($reason));reason=$reason;maxBytes=12GB}
}
function Get-WindowsHomeMedia {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Uri,
          [Parameter(Mandatory)][string]$Sha256,
          [Parameter(Mandatory)][string]$Root,
          [Parameter(Mandatory)][string]$VmName)
    $request=Test-WindowsHomeMediaRequest -Uri $Uri -Sha256 $Sha256 -Root $Root -VmName $VmName
    if(-not $request.accepted){throw $request.reason}
    $marker=Get-Content -LiteralPath (Join-Path $Root 'probe-owner.json') -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    if($marker.schema -ne 1 -or $marker.root -cne $Root.Replace('\','/') -or $marker.name -cne $VmName -or $marker.status -ne 'created'){throw 'Owned probe marker required before media download.'}
    $directory=Join-Path $Root 'media'
    New-Item -ItemType Directory -Path $directory -Force -ErrorAction Stop | Out-Null
    if(((Get-Item -LiteralPath $directory).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'Media directory is a reparse point.'}
    $destination=Join-Path $directory 'windows-home.iso'
    if(Test-Path -LiteralPath $destination){
        if((Get-FileHash -LiteralPath $destination).Hash -ine $Sha256){throw 'Existing media differs; refusing overwrite.'}
        return [pscustomobject]@{path=$destination;sha256=$Sha256;bytes=(Get-Item -LiteralPath $destination).Length;verified=$true}
    }
    $temp=Join-Path $directory ('download-'+[guid]::NewGuid().ToString('N')+'.partial')
    $client=[Net.Http.HttpClient]::new();$response=$null;$input=$null;$output=$null
    $client.Timeout=[TimeSpan]::FromMinutes(30)
    try {
        $response=$client.GetAsync($Uri,[Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
        [void]$response.EnsureSuccessStatusCode()
        if($response.RequestMessage.RequestUri.Scheme -ne 'https' -or $response.RequestMessage.RequestUri.DnsSafeHost -ine 'software.download.prss.microsoft.com'){throw 'Unexpected media redirect.'}
        if($response.Content.Headers.ContentLength -and $response.Content.Headers.ContentLength -gt $request.maxBytes){throw 'Media exceeds transfer bound.'}
        $input=$response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
        $output=[IO.File]::Open($temp,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        $buffer=[byte[]]::new(1MB);$count=[long]0;$next=[DateTime]::UtcNow.AddSeconds(15)
        while(($read=$input.Read($buffer,0,$buffer.Length)) -gt 0){
            $count+=$read
            if($count -gt $request.maxBytes){throw 'Media stream exceeds transfer bound.'}
            $output.Write($buffer,0,$read)
            if([DateTime]::UtcNow -ge $next){Write-Host ('MEDIA DOWNLOAD: '+$count+' bytes');$next=[DateTime]::UtcNow.AddSeconds(15)}
        }
        $output.Dispose();$output=$null
        if($count -le 0 -or ($response.Content.Headers.ContentLength -and $count -ne $response.Content.Headers.ContentLength)){throw 'Incomplete media download.'}
        if((Get-FileHash -LiteralPath $temp -Algorithm SHA256).Hash -ine $Sha256){throw 'Published media hash mismatch.'}
        [IO.File]::Move($temp,$destination)
        return [pscustomobject]@{path=$destination;sha256=$Sha256;bytes=$count;verified=$true}
    } finally {
        if($output){$output.Dispose()};if($input){$input.Dispose()};if($response){$response.Dispose()};$client.Dispose()
        if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue}
    }
}
