$ErrorActionPreference='Stop'
$module=Join-Path $PSScriptRoot '../scripts/windows-state-roundtrip.ps1'
if(-not (Test-Path -LiteralPath $module)){throw 'ASSERT: portable fixture credential helper missing'}
. $module
$keys=@('GITHUB_ACTIONS','DEVBOX_ISOLATED_TEST','GITHUB_EVENT_NAME','GITHUB_REPOSITORY','RESTIC_PASSWORD','GH_TOKEN')
$previous=@{};foreach($key in $keys){$previous[$key]=[Environment]::GetEnvironmentVariable($key)}
function Assert-Refused([scriptblock]$Action){
    $refused=$false;try{& $Action|Out-Null}catch{$refused=$true}
    if(-not $refused){throw 'ASSERT: expected portable credential refusal'}
}
try {
    $env:GITHUB_ACTIONS='true';$env:DEVBOX_ISOLATED_TEST='1';$env:GITHUB_EVENT_NAME='workflow_dispatch';$env:GITHUB_REPOSITORY='fixture/repo';$env:RESTIC_PASSWORD='fixture-encryption-key-only';$env:GH_TOKEN='fixture-token-only'
    if(-not (Get-Command Publish-WindowsStateRoundtrip -ErrorAction SilentlyContinue)){throw 'ASSERT: whole-VM encrypted publisher missing'}
    if(-not (Get-Command Restore-WindowsStateRoundtrip -ErrorAction SilentlyContinue)){throw 'ASSERT: exact-generation fresh-host restore missing'}
    $id=[guid]'11111111-1111-4111-8111-111111111111'
    $one=Get-WindowsStatePortableFixtureCredential -VmId $id
    $two=Get-WindowsStatePortableFixtureCredential -VmId $id
    if($one.UserName -cne 'DevBoxFixture' -or $one.GetNetworkCredential().Password -cne $two.GetNetworkCredential().Password){throw 'ASSERT: same backup key and VM must derive same fixture credential'}
    if($one.GetNetworkCredential().Password.Length -lt 64){throw 'ASSERT: fixture credential entropy/length insufficient'}
    $other=Get-WindowsStatePortableFixtureCredential -VmId ([guid]'22222222-2222-4222-8222-222222222222')
    if($one.GetNetworkCredential().Password -ceq $other.GetNetworkCredential().Password){throw 'ASSERT: distinct VM identities need distinct fixture credentials'}
    $env:RESTIC_PASSWORD='different-fixture-key'
    $other=Get-WindowsStatePortableFixtureCredential -VmId $id
    if($one.GetNetworkCredential().Password -ceq $other.GetNetworkCredential().Password){throw 'ASSERT: distinct backup keys need distinct fixture credentials'}
    $env:RESTIC_PASSWORD='fixture-encryption-key-only'
    foreach($key in $keys){
        $value=[Environment]::GetEnvironmentVariable($key)
        try{[Environment]::SetEnvironmentVariable($key,'');Assert-Refused {Get-WindowsStatePortableFixtureCredential -VmId $id}}
        finally{[Environment]::SetEnvironmentVariable($key,$value)}
    }
    Assert-Refused {Get-WindowsStatePortableFixtureCredential -VmId ([guid]::Empty)}
    foreach($foreign in @('C:/Windows','D:/user','E:/unowned')){Assert-Refused {Publish-WindowsStateRoundtrip -Root $foreign -VmId $id -Checkpoint $null -Baseline $null}}
    Assert-Refused {Restore-WindowsStateRoundtrip -ExpectedGeneration 'production'}
    # Mutable producer state must be revalidated at live recovery boundaries.
    $script:liveProducer=[ordered]@{status='in_progress';conclusion=$null;run_attempt=1;head_sha=('a'*40);event='workflow_dispatch';path='.github/workflows/windows-state-probe-validate.yml'}
    function gh {$global:LASTEXITCODE=0;$script:liveProducer|ConvertTo-Json -Compress}
    try {
        Assert-WindowsStateLiveProducer -ProducerRun '123' -ProducerAttempt '1' -SourceSha ('a'*40)
        foreach($case in @(@('status','completed'),@('conclusion','failure'),@('run_attempt',2),@('head_sha',('b'*40)),@('event','push'),@('path','other.yml'))){
            $field=$case[0];$old=$script:liveProducer[$field]
            try {$script:liveProducer[$field]=$case[1];Assert-Refused {Assert-WindowsStateLiveProducer -ProducerRun '123' -ProducerAttempt '1' -SourceSha ('a'*40)}}
            finally {$script:liveProducer[$field]=$old}
        }
        # A producer accepted initially must be rejected after a later failure.
        Assert-WindowsStateLiveProducer -ProducerRun '123' -ProducerAttempt '1' -SourceSha ('a'*40)
        $script:liveProducer.status='completed';$script:liveProducer.conclusion='failure'
        Assert-Refused {Assert-WindowsStateLiveProducer -ProducerRun '123' -ProducerAttempt '1' -SourceSha ('a'*40)}
    } finally {Remove-Item Function:gh}
    Write-Output 'PORTABLE FIXTURE CREDENTIAL DETERMINISM + DOMAIN/CONTEXT REFUSALS: PASS'
} finally {foreach($key in $keys){[Environment]::SetEnvironmentVariable($key,$previous[$key])}}
