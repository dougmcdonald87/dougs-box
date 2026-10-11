# Non-invasive preflight for the existing GitHub->Tailscale OIDC configuration.
# Prints only pass/fail indicators, never JWTs or the configured credential values.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Fail([string]$reason) {
    Write-Error "DEVBOX OIDC PREFLIGHT FAILED: $reason"
    exit 1
}

$clientId = [string]$env:TS_OAUTH_CLIENT_ID
$audience = [string]$env:TS_AUDIENCE
if ([string]::IsNullOrWhiteSpace($clientId) -or [string]::IsNullOrWhiteSpace($audience)) {
    Fail 'The GitHub devbox Environment is missing TS_OAUTH_CLIENT_ID or TS_AUDIENCE.'
}
if ($clientId -ne $clientId.Trim() -or $audience -ne $audience.Trim()) {
    Fail 'A GitHub OIDC credential value contains leading or trailing whitespace. Copy both values directly from the existing Tailscale trust credential.'
}

# Tailscale generates this audience from the federated identity client ID.
# A mismatch proves that the two saved GitHub values cannot describe the same
# generated Tailscale federated identity.
if ($audience -cne ('api.tailscale.com/' + $clientId)) {
    Fail 'The TS_AUDIENCE value is not api.tailscale.com/ followed by TS_OAUTH_CLIENT_ID. Recopy both values from the same existing OIDC credential.'
}
Write-Output 'DEVBOX OIDC CHECK: GitHub Client ID and Audience are internally consistent.'

if ([string]::IsNullOrWhiteSpace($env:ACTIONS_ID_TOKEN_REQUEST_URL) -or
    [string]::IsNullOrWhiteSpace($env:ACTIONS_ID_TOKEN_REQUEST_TOKEN)) {
    Fail 'GitHub has not exposed the OIDC request endpoint. Verify id-token: write permission.'
}
$requestUrl = [string]$env:ACTIONS_ID_TOKEN_REQUEST_URL
$separator = if ($requestUrl.Contains('?')) { '&' } else { '?' }
$requestUrl += $separator + 'audience=' + [Uri]::EscapeDataString($audience)
try {
    $tokenResponse = Invoke-RestMethod -Uri $requestUrl -Method Get -Headers @{
        Authorization = 'Bearer ' + $env:ACTIONS_ID_TOKEN_REQUEST_TOKEN
    } -ErrorAction Stop
    $encodedPayload = ([string]$tokenResponse.value).Split('.')[1]
    if ([string]::IsNullOrWhiteSpace($encodedPayload)) { Fail 'GitHub returned an incomplete OIDC JWT.' }
    $b64 = $encodedPayload.Replace('-', '+').Replace('_', '/')
    $b64 = $b64.PadRight([int]([Math]::Ceiling($b64.Length / 4.0) * 4), '=')
    $claims = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b64)) |
        ConvertFrom-Json -ErrorAction Stop
} catch {
    Fail 'GitHub could not issue or decode the OIDC token. Check workflow id-token permission and environment.'
}

$expectedSubject = 'repo:dougmcdonald87@220090710/dougs-box@1414179011:environment:devbox'
$expectedWorkflow = 'dougmcdonald87/dougs-box/.github/workflows/devbox.yml@refs/heads/main'
if ($claims.iss -cne 'https://token.actions.githubusercontent.com') {
    Fail 'The token issuer is not the documented GitHub Actions OIDC issuer.'
}
if ($claims.aud -cne $audience) {
    Fail 'GitHub-issued token audience differs from saved TS_AUDIENCE.'
}
if ($claims.sub -cne $expectedSubject) {
    Fail "The real GitHub OIDC subject differs from the subject shown in the existing Tailscale credential. Actual subject: $($claims.sub)"
}
if ($claims.workflow_ref -cne $expectedWorkflow) {
    Fail 'The GitHub token refers to a different workflow than the configured DevBox workflow.'
}
Write-Output 'DEVBOX OIDC CHECK: GitHub issuer, audience, immutable subject and workflow_ref match the documented configuration.'
Write-Output 'DEVBOX OIDC CHECK: PASS. This does not independently prove that the Client ID is recognised by Tailscale.'
