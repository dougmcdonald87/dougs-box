$ErrorActionPreference='Stop'
$source=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../scripts/windows-state-operator.ps1') -Raw
$tokens=$null;$errors=$null
[void][System.Management.Automation.Language.Parser]::ParseInput($source,[ref]$tokens,[ref]$errors)
if(@($errors).Count){throw ('Operator syntax error: '+($errors | Out-String))}
$save=$source.IndexOf("-Mode 'save'")
$publish=$source.IndexOf('$result=Publish-WindowsStateRoundtrip')
$guard=$source.IndexOf('if($result.published -ne $true')
$finish=$source.IndexOf("if(`$Operation -eq 'Finish')")
$stop=$source.IndexOf('Stop-VM -VM')
$receipt=$source.IndexOf('[ordered]@{schema=1;operationId')
if($save -lt 0 -or $publish -lt 0 -or $guard -lt 0 -or $finish -lt 0 -or $stop -lt 0 -or $receipt -lt 0){throw 'Finish guard markers missing'}
if(-not ($save -lt $publish -and $publish -lt $guard -and $guard -lt $finish -and $finish -lt $stop -and $stop -lt $receipt)){throw 'Finish can shut down before verified checkpoint publish'}
if($source.Contains('-Mode $Operation.ToLowerInvariant()')){throw 'Unsafe old Finish export remains'}
if(-not $source.Contains("(Get-VM -Id `$vmId).State -ne 'Off'")){throw 'Guest shutdown state verification missing'}
Write-Output 'FINISH ORDER AND POWERSHELL PARSE: PASS'
