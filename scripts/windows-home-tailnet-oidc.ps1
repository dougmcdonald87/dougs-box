# Pilot-only GitHub OIDC preflight. Does not provision trust or alter the original DevBox.
[CmdletBinding()]
param([Parameter(Mandatory)][string]$ClientId)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$expectedRef='refs/heads/pilot/windows-home-connection-20261015'
$expectedWorkflow='dougmcdonald87/dougs-box/.github/workflows/windows-state-probe-validate.yml@'+$expectedRef
$expectedSubject='repo:dougmcdonald87@220090710/dougs-box@1414179011:environment:devbox'
if($env:GITHUB_ACTIONS -cne 'true' -or $env:GITHUB_EVENT_NAME -cne 'workflow_dispatch' -or
   $env:GITHUB_REF -cne $expectedRef -or $env:GITHUB_REPOSITORY -cne 'dougmcdonald87/dougs-box'){
 throw 'Pilot tailnet preflight denied outside the exact manual workflow.'
}
if([string]::IsNullOrWhiteSpace($ClientId) -or $ClientId -cnotmatch '^[A-Za-z0-9_-]{6,128}$'){
 throw 'Dedicated PILOT_TAILSCALE_OIDC_CLIENT_ID is missing or malformed. Never substitute original DevBox trust.'
}
if([string]::IsNullOrWhiteSpace($env:ACTIONS_ID_TOKEN_REQUEST_URL) -or
   [string]::IsNullOrWhiteSpace($env:ACTIONS_ID_TOKEN_REQUEST_TOKEN)){
 throw 'Pilot OIDC endpoint missing; job must have id-token: write.'
}
$audience='api.tailscale.com/'+$ClientId
$uri=[string]$env:ACTIONS_ID_TOKEN_REQUEST_URL
$uri += $(if($uri.Contains('?')){'&'}else{'?'})+'audience='+[Uri]::EscapeDataString($audience)
try{
 $reply=Invoke-RestMethod -Uri $uri -Method Get -Headers @{Authorization='Bearer '+$env:ACTIONS_ID_TOKEN_REQUEST_TOKEN} -ErrorAction Stop
 $parts=([string]$reply.value).Split('.')
 if($parts.Length -ne 3){throw 'OIDC JWT format'}
 $encoded=$parts[1].Replace('-','+').Replace('_','/')
 $encoded=$encoded.PadRight([int]([Math]::Ceiling($encoded.Length/4.0)*4),'=')
 $claims=([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($encoded))|ConvertFrom-Json -ErrorAction Stop)
}catch{
 throw 'Pilot OIDC token unavailable or malformed; no secret value printed.'
}
if($claims.iss -cne 'https://token.actions.githubusercontent.com' -or
   $claims.aud -cne $audience -or $claims.sub -cne $expectedSubject -or
   $claims.workflow_ref -cne $expectedWorkflow -or $claims.ref -cne $expectedRef){
 throw 'Pilot OIDC identity did not match pinned repository, environment, branch and workflow.'
}
Write-Output 'PILOT_TAILNET_OIDC_CONTEXT_VERIFIED=true'
Write-Output 'This is not proof that the separate pilot OAuth credential exists in Tailscale.'
