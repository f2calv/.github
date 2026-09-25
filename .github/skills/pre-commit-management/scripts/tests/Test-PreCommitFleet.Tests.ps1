#Requires -Version 7.4

BeforeAll {
  . (Join-Path $PSScriptRoot '..\Test-PreCommitFleet.ps1') -RepositoryPath $TestDrive

  function New-TestRepository {
    param(
      [Parameter(Mandatory = $true)]
      [string]$Path,

      [Parameter()]
      [switch]$OmitConfig
    )

    $null = New-Item -ItemType Directory -Path (Join-Path $Path '.github\workflows') -Force
    & git -C $Path init --quiet
    if (-not $OmitConfig) {
      Set-Content -LiteralPath (Join-Path $Path '.pre-commit-config.yaml') -Value @'
default_install_hook_types: [pre-push]
repos:
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v6.0.0
'@
    }
    Set-Content -LiteralPath (Join-Path $Path '.github\workflows\ci.yml') -Value @'
name: ci
jobs:
  lint:
    uses: example/workflows/.github/workflows/lint.yml@v1
  release:
    needs: [lint]
'@
      Set-Content -LiteralPath (Join-Path $Path '.github\dependabot.yml') -Value @'
version: 2
updates:
  - package-ecosystem: pre-commit
    directory: /
    schedule:
      interval: weekly
'@
    }
}

Describe 'Get-PreCommitRepositoryState' {
    It 'accepts a repository satisfying the fleet contract' {
        $repository = Join-Path $TestDrive 'compliant'
        New-TestRepository -Path $repository

        $state = Get-PreCommitRepositoryState -Path $repository

        $state.Compliant | Should -BeTrue
        $state.Hooks | Should -Match 'pre-commit-hooks@v6.0.0'
    }

    It 'reports a missing pre-commit configuration' {
        $repository = Join-Path $TestDrive 'missing-config'
        New-TestRepository -Path $repository -OmitConfig

        $state = Get-PreCommitRepositoryState -Path $repository

        $state.Config | Should -BeFalse
        $state.Compliant | Should -BeFalse
    }
}
