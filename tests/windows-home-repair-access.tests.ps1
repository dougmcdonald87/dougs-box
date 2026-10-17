$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$path=Join-Path $PSScriptRoot '../scripts/windows-home-repair-access.ps1'
if(-not(Test-Path $path)){throw 'ASSERT: scoped pilot repair access missing'}
$t=$null;$e=$null;$ast=[System.Management.Automation.Language.Parser]::ParseFile($path,[ref]$t,[ref]$e)
$f=$ast.Find({param($n)$n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq 'Get-WindowsHomeRepairAccessPolicy'},$true)
if(-not $f){throw 'ASSERT: repair network policy missing'};Invoke-Expression $f.Extent.Text
foreach($ip in @('100.64.0.1','100.127.255.254')){
 $policy=Get-WindowsHomeRepairAccessPolicy $ip
 if($policy.LocalAddress -cne $ip -or $policy.RemoteAddress -cne '100.64.0.0/10' -or $policy.LocalPort -ne 5985 -or $policy.Basic -ne $false -or $policy.AllowUnencrypted -ne $false){throw 'ASSERT: repair access scope weakened'}
}
foreach($ip in @('100.63.255.255','100.128.0.1','127.0.0.1','0.0.0.0','192.168.1.2','::1','100.64.0.999','100.064.0.1')){
 $failed=$false;try{Get-WindowsHomeRepairAccessPolicy $ip|Out-Null}catch{$failed=$true};if(-not $failed){throw ('ASSERT: foreign/noncanonical repair IP accepted '+$ip)}
}
Write-Host 'REPAIR ACCESS POLICY: PASS (10 boundaries)'
