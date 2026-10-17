$ErrorActionPreference='Stop'
$p=Join-Path $PSScriptRoot '../scripts/windows-home-repair-inspect.ps1';$t=$null;$e=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($p,[ref]$t,[ref]$e)
$f=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq 'Test-WindowsHomeInspectionVmPath'},$true)
if(-not $f){throw 'ASSERT missing shared inspection path contract'}
Invoke-Expression $f.Extent.Text
$root='E:/DevBox/Tools/WindowsStateProbe/probe-38647908553-1';$name='DevBoxWindowsState-38647908553-1'
foreach($path in @($root,($root+'/'+$name),($root.Replace('/','\')+'\'))){if(-not(Test-WindowsHomeInspectionVmPath $root $name $path)){throw 'ASSERT native owned layout refused'}}
foreach($path in @('E:/other',($root+'-other'),($root+'/unrelated'),($root+'/'+$name+'/Virtual Machines'))){if(Test-WindowsHomeInspectionVmPath $root $name $path){throw 'ASSERT unrelated path accepted'}}
Write-Host 'INSPECTION OWNED PATH: PASS (7 exact layouts/boundaries)'
