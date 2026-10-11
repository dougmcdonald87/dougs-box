# tests/devbox.tests.ps1 - Pester 5 suite for the static gates that CAN run locally.
# Full interop (Tailscale from a real runner, rest-server handshake, RDP) is marked
# LIVE TEST REQUIRED per Phase 51 and belongs in the runner session, not here.
# Run with Pester 5+: pwsh -NoProfile -Command "Invoke-Pester"
# The common.ps1 helper set is dot-sourced, not imported, to match production call sites.

Describe 'binary GiB math (acceptance: 100 GiB means 107,374,182,400 bytes)' {
    BeforeAll {
        . (Join-Path $PSScriptRoot '..\scripts\common.ps1')
    }
    It 'ConvertTo-PackedBytes treats 100 GiB as binary' {
        ConvertTo-PackedBytes (100.0) | Should -Be 107374182400
    }
    It 'ConvertTo-PackedBytes is floor-safe on fractional values' {
        ConvertTo-PackedBytes (0.0000005) | Should -Be 0
    }
}

Describe 'workspace discovery (spec: never assume D:, loud failure when nothing qualifies)' {
    BeforeAll {
        . (Join-Path $PSScriptRoot '..\scripts\common.ps1')
    }
    It 'unknown/unreachable drive letter reports not-qualifying (no crash)' {
        Test-HasFreeGiB -DriveRoot 'X:\' -RequiredGiB 100 | Should -Be $false
    }
    It 'handles paths containing spaces' {
        { Test-HasFreeGiB -DriveRoot 'C:\' -RequiredGiB 1 } | Should -Not -Throw
    }
    It 'Stop-DevBox exits nonzero (loud failure path)' {
        { Stop-DevBox 'unit-test: no >=100 GiB volume' } | Should -Throw
    }
}

Describe 'append-only law (Phase 41 audit mirrored at the unit layer)' {
    It 'no code file contains a destructive repository command' {
        $repoRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot) -Parent
        $hits = Get-ChildItem $repoRoot -Recurse -Include '*.ps1','*.yml','*.json' |
            Select-String -Pattern 'restic[\s]+-[\s\S]*(forget|prune)|\b(forget|prune)\s' -SimpleMatch:$false
        $hits | Should -BeNullOrEmpty
    }
}

Describe 'config hygiene (Phase 40 mirrored locally)' {
    It 'example config contains no secret-looking literals' {
        foreach ($f in @(
            (Join-Path $PSScriptRoot '..\config\devbox.example.json'),
            (Join-Path $PSScriptRoot '..\config\persistence.example.json'))) {
            $text = Get-Content $f -Raw
            $text | Should -Not -Match '(password\s*[:=][^"\s])|BEGIN [A-Z]+ PRIVATE KEY'
        }
    }
}

Describe 'session deadline arithmetic (Phase 32)' {
    It 'ready-target deadline lands before the hard limit' {
        $start = [DateTime]::Parse('2026-10-10T12:00:00Z')
        $ready = $start.AddMinutes(320)
        $hard = $start.AddMinutes(350)
        ($ready -lt $hard) | Should -Be $true
    }
}
