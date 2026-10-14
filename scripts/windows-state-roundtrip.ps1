$ErrorActionPreference='Stop'
function Assert-WindowsStateRoundtripContext {
    if($env:GITHUB_ACTIONS -cne 'true' -or $env:DEVBOX_ISOLATED_TEST -cne '1' -or $env:GITHUB_EVENT_NAME -cne 'workflow_dispatch' -or $env:GITHUB_REPOSITORY -cnotmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' -or [string]::IsNullOrWhiteSpace($env:RESTIC_PASSWORD) -or [string]::IsNullOrWhiteSpace($env:GH_TOKEN)){
        throw 'Only an isolated authenticated manual fixture transfer is allowed.'
    }
}
function Get-WindowsStatePortableFixtureCredential {
    param([Parameter(Mandatory)][guid]$VmId)
    Assert-WindowsStateRoundtripContext
    if($VmId -eq [guid]::Empty){throw 'Portable fixture VM identity required.'}
    $key=[Text.Encoding]::UTF8.GetBytes($env:RESTIC_PASSWORD)
    $hmac=[Security.Cryptography.HMACSHA256]::new($key)
    try {
        $message=[Text.Encoding]::UTF8.GetBytes('DevBoxWindowsStateFixture-v1|'+$VmId.ToString('D').ToLowerInvariant())
        $secret='Fixture!1'+[Convert]::ToHexString($hmac.ComputeHash($message))
        Write-Host ('::add-mask::'+$secret)
        [pscredential]::new('DevBoxFixture',(ConvertTo-SecureString $secret -AsPlainText -Force))
    } finally {$hmac.Dispose();[Array]::Clear($key,0,$key.Length)}
}
