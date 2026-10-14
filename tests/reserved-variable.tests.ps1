$ErrorActionPreference='Stop'
$project=Split-Path -Parent $PSScriptRoot
$failures=@()
foreach($file in (Get-ChildItem (Join-Path $project 'scripts'),(Join-Path $project 'tests') -Filter *.ps1 -Recurse)){
    $tokens=$null;$errors=$null
    $ast=[System.Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
    if($errors.Count){throw ('Parse errors: '+$file.Name)}
    foreach($assignment in $ast.FindAll({param($node) $node -is [System.Management.Automation.Language.AssignmentStatementAst]},$true)){
        foreach($variable in $assignment.Left.FindAll({param($node) $node -is [System.Management.Automation.Language.VariableExpressionAst]},$true)){
            if($variable.VariablePath.UserPath -match '^(?:(?:global|script|local|private):)?home$'){
                $failures+=($file.Name+':'+$assignment.Extent.StartLineNumber)
            }
        }
    }
}
if($failures.Count){throw ('Read-only HOME assignment refused: '+($failures -join ', '))}
Write-Output 'RESERVED HOME VARIABLE REGRESSION: PASS'
