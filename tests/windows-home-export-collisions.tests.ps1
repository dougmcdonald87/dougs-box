$ErrorActionPreference='Stop'
$p=Join-Path $PSScriptRoot '../scripts/windows-home-repair-inspect.ps1'
if(-not(Test-Path $p)){throw 'ASSERT: read-only export collision inspection missing'}
$t=$null;$e=$null;$a=[System.Management.Automation.Language.Parser]::ParseFile($p,[ref]$t,[ref]$e)
$f=$a.Find({param($n)$n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq 'Get-WindowsHomeExportNameCollisions'},$true)
if(-not $f){throw 'ASSERT: export collision grouping missing'};Invoke-Expression $f.Extent.Text
$refs=@([pscustomobject]@{path='E:/owned/restored-disks/windows-home.vhdx'},[pscustomobject]@{path='E:/owned/checkpoints/old/windows-home.vhdx'})
$r=@(Get-WindowsHomeExportNameCollisions $refs);if($r.Count -ne 1 -or $r[0].paths.Count -ne 2){throw 'ASSERT: distinct same-name VHD paths not reported'}
$refs[1].path='e:/OWNED/restored-disks/WINDOWS-HOME.VHDX'
if(@(Get-WindowsHomeExportNameCollisions $refs).Count){throw 'ASSERT: repeated same native path is not an export collision'}
$refs[1].path='E:/owned/restored-disks/child.avhdx'
if(@(Get-WindowsHomeExportNameCollisions $refs).Count){throw 'ASSERT: different export names falsely collide'}
Write-Host 'EXPORT COLLISION INSPECTOR: PASS (3 mapping cases)'
