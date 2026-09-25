#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.1' }

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot '../Test-Dockerfile.ps1'
    . $scriptPath

    $script:Compliant = @'
# syntax=docker/dockerfile:1
#
# Example image built from a single Dockerfile.
FROM --platform=$BUILDPLATFORM golang:1-trixie AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN --mount=type=cache,target=/go/pkg/mod,sharing=shared \
    go mod download
COPY . .
ARG TARGETARCH
ARG TARGETVARIANT
RUN <<EOF
set -eux
case "${TARGETARCH}${TARGETVARIANT}" in
    amd64) export GOARCH=amd64 ;;
    arm64) export GOARCH=arm64 ;;
    *) echo "unsupported platform" >&2; exit 1 ;;
esac
go build -trimpath -o /out/app ./src/app
EOF

FROM gcr.io/distroless/static-debian13:nonroot AS final
WORKDIR /app
COPY --link --from=build /out/app .
ARG GIT_REPOSITORY=n/a
ENV GIT_REPOSITORY=$GIT_REPOSITORY
ARG GIT_BRANCH=n/a
ARG GIT_COMMIT=n/a
ARG GIT_TAG=n/a
ARG GITHUB_WORKFLOW=n/a
ARG GITHUB_RUN_ID=0
ARG GITHUB_RUN_NUMBER=0
LABEL org.opencontainers.image.title="example" \
    org.opencontainers.image.description="Example image" \
    org.opencontainers.image.source="https://example.com/source" \
    org.opencontainers.image.licenses="MIT" \
    org.opencontainers.image.version="$GIT_TAG" \
    org.opencontainers.image.revision="$GIT_COMMIT"
USER nonroot:nonroot
ENTRYPOINT ["/app/app"]
'@ -replace "`r`n", "`n"

    function script:New-Fixture {
        param(
            [Parameter(Mandatory = $true)][string]$Content,
            [string]$Name = 'Dockerfile',
            [string]$DockerIgnore = "*`n!src/**`n",
            [switch]$NoDockerIgnore
        )

        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
        New-Item -ItemType Directory -Path (Join-Path $root '.git') -Force | Out-Null
        $file = Join-Path $root $Name
        Set-Content -LiteralPath $file -Value $Content -NoNewline
        if (-not $NoDockerIgnore) {
            Set-Content -LiteralPath (Join-Path $root '.dockerignore') -Value $DockerIgnore -NoNewline
        }
        return $file
    }

    function script:Get-Rule {
        param([Parameter(Mandatory = $true)][string]$Content, [string]$Name = 'Dockerfile', [string]$ImageProfile = 'auto')

        $file = New-Fixture -Content $Content -Name $Name
        @(Get-DockerfileFinding -FilePath $file -ImageProfile $ImageProfile | ForEach-Object { $_.Rule })
    }
}

Describe 'Read-DockerfileModel' {
    It 'joins continuations, skips interleaved comments and reads heredoc bodies' {
        $model = Read-DockerfileModel -Line @(
            '# syntax=docker/dockerfile:1'
            '# check=skip=JSONArgsRecommended'
            'FROM alpine:3.22 AS build'
            'RUN --mount=type=cache,target=/root/.cache \'
            '    # interleaved comment'
            '    --network=none <<EOF'
            'set -eux'
            'echo hello'
            'EOF'
            'COPY . .'
        )

        $model.Directives['syntax'] | Should -Be 'docker/dockerfile:1'
        $model.Directives['check'] | Should -Be 'skip=JSONArgsRecommended'
        @($model.Instructions).Count | Should -Be 3
        $model.Instructions[1].Keyword | Should -Be 'RUN'
        $model.Instructions[1].Line | Should -Be 4
        $model.Instructions[1].Arguments | Should -Match '--network=none'
        $model.Instructions[1].Heredocs[0] | Should -Be "set -eux`necho hello"
        $model.Instructions[2].Keyword | Should -Be 'COPY'
        $model.Stages[0].Name | Should -Be 'build'
    }

    It 'resolves global ARG defaults in FROM' {
        $model = Read-DockerfileModel -Line @('ARG BASE=example.com/image:1.2', 'FROM ${BASE} AS final')
        $model.Stages[0].Resolved | Should -Be 'example.com/image:1.2'
    }

    It 'treats ARG without a value as undefaulted' {
        $pair = @(ConvertFrom-KeyValueArgument -Arguments 'GIT_COMMIT')
        $pair[0].Name | Should -Be 'GIT_COMMIT'
        $pair[0].Value | Should -BeNullOrEmpty
    }
}

Describe 'Get-DockerfileFinding' {
    It 'reports nothing for a compliant published Dockerfile' {
        Get-Rule -Content $script:Compliant | Should -BeNullOrEmpty
    }

    It 'reports <Rule> when <Scenario>' -TestCases @(
        @{ Rule = 'DF001'; Scenario = 'the syntax directive is missing'; Find = '# syntax=docker/dockerfile:1'; Replace = '# example' }
        @{ Rule = 'DF002'; Scenario = 'an image is untagged'; Find = 'golang:1-trixie'; Replace = 'golang' }
        @{ Rule = 'DF002'; Scenario = 'an image uses latest'; Find = 'golang:1-trixie'; Replace = 'golang:latest' }
        @{ Rule = 'DF003'; Scenario = 'the final stage sets a platform'; Find = 'FROM gcr.io'; Replace = 'FROM --platform=linux/arm64 gcr.io' }
        @{ Rule = 'DF004'; Scenario = 'a build stage is not pinned to BUILDPLATFORM'; Find = 'FROM --platform=$BUILDPLATFORM golang'; Replace = 'FROM golang' }
        @{ Rule = 'DF005'; Scenario = 'USER is missing'; Find = 'USER nonroot:nonroot'; Replace = '' }
        @{ Rule = 'DF005'; Scenario = 'USER is root'; Find = 'USER nonroot:nonroot'; Replace = 'USER root' }
        @{ Rule = 'DF006'; Scenario = 'ENTRYPOINT uses shell form'; Find = 'ENTRYPOINT ["/app/app"]'; Replace = 'ENTRYPOINT /app/app' }
        @{ Rule = 'DF007'; Scenario = 'sh -c lacks exec'; Find = 'ENTRYPOINT ["/app/app"]'; Replace = 'ENTRYPOINT ["sh", "-c", "/app/app ${ARGS}"]' }
        @{ Rule = 'DF008'; Scenario = 'apt omits --no-install-recommends'; Find = 'WORKDIR /app'; Replace = "WORKDIR /app`nRUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*" }
        @{ Rule = 'DF009'; Scenario = 'apt lists are not removed'; Find = 'WORKDIR /app'; Replace = "WORKDIR /app`nRUN apt-get update && apt-get install -y --no-install-recommends curl" }
        @{ Rule = 'DF010'; Scenario = 'the distribution is upgraded'; Find = 'WORKDIR /app'; Replace = "WORKDIR /app`nRUN apt-get update && apt-get upgrade -y && rm -rf /var/lib/apt/lists/*" }
        @{ Rule = 'DF011'; Scenario = 'a heredoc lacks set -e'; Find = "set -eux`ncase"; Replace = 'case' }
        @{ Rule = 'DF012'; Scenario = 'the platform case has no default arm'; Find = '    *) echo "unsupported platform" >&2; exit 1 ;;'; Replace = '' }
        @{ Rule = 'DF012'; Scenario = 'the platform if-chain has no else'; Find = 'WORKDIR /app'; Replace = "WORKDIR /app`nARG TARGETPLATFORM`nRUN if [ `"`$TARGETPLATFORM`" = `"linux/amd64`" ]; then echo x; fi" }
        @{ Rule = 'DF013'; Scenario = 'a provenance ARG has no default'; Find = 'ARG GIT_COMMIT=n/a'; Replace = 'ARG GIT_COMMIT' }
        @{ Rule = 'DF014'; Scenario = 'a provenance ARG is missing'; Find = 'ARG GITHUB_RUN_ID=0'; Replace = '' }
        @{ Rule = 'DF015'; Scenario = 'an OCI label is missing'; Find = 'org.opencontainers.image.licenses='; Replace = 'org.example.licenses=' }
        @{ Rule = 'DF016'; Scenario = 'HEALTHCHECK is declared'; Find = 'USER nonroot:nonroot'; Replace = "HEALTHCHECK CMD [`"/app/app`", `"health`"]`nUSER nonroot:nonroot" }
        @{ Rule = 'DF017'; Scenario = 'a download is piped to a shell'; Find = 'go build'; Replace = "curl -fsSL https://example.com/install.sh | sh`ngo build" }
        @{ Rule = 'DF018'; Scenario = 'an instruction is commented out'; Find = 'USER nonroot:nonroot'; Replace = "#RUN echo parked`nUSER nonroot:nonroot" }
        @{ Rule = 'DF021'; Scenario = 'the runtime installs a -dev package'; Find = 'WORKDIR /app'; Replace = "WORKDIR /app`nRUN apt-get update && apt-get install -y --no-install-recommends libexample-dev && rm -rf /var/lib/apt/lists/*" }
        @{ Rule = 'DF022'; Scenario = 'a secret-like ENV has a value'; Find = 'WORKDIR /app'; Replace = "WORKDIR /app`nENV API_TOKEN=abc123" }
        @{ Rule = 'DF023'; Scenario = 'the last stage is not named final'; Find = 'AS final'; Replace = 'AS runtime' }
    ) {
        param($Rule, $Find, $Replace)

        $content = $script:Compliant.Replace($Find, $Replace)
        $content | Should -Not -Be $script:Compliant
        Get-Rule -Content $content | Should -Contain $Rule
    }

    It 'accepts an apt install whose lists live in a cache mount' {
        $content = $script:Compliant.Replace('WORKDIR /app', "WORKDIR /app`nRUN --mount=type=cache,target=/var/lib/apt,sharing=locked apt-get update && apt-get install -y --no-install-recommends curl")
        Get-Rule -Content $content | Should -Not -Contain 'DF009'
    }

    It 'accepts sh -c when the command is exec-ed' {
        $content = $script:Compliant.Replace('ENTRYPOINT ["/app/app"]', 'ENTRYPOINT ["sh", "-c", "exec /app/app ${ARGS}"]')
        Get-Rule -Content $content | Should -Not -Contain 'DF007'
    }

    It 'reports a missing .dockerignore' {
        $file = New-Fixture -Content $script:Compliant -NoDockerIgnore
        @(Get-DockerfileFinding -FilePath $file | ForEach-Object { $_.Rule }) | Should -Contain 'DF019'
    }

    It 'reports a deny-list .dockerignore' {
        $file = New-Fixture -Content $script:Compliant -DockerIgnore "bin/`nobj/`n"
        @(Get-DockerfileFinding -FilePath $file | ForEach-Object { $_.Rule }) | Should -Contain 'DF020'
    }

    It 'prefers a Dockerfile-specific ignore file' {
        $file = New-Fixture -Content $script:Compliant -DockerIgnore "bin/`n"
        Set-Content -LiteralPath "$file.dockerignore" -Value "*`n!src/**`n"
        @(Get-DockerfileFinding -FilePath $file | ForEach-Object { $_.Rule }) | Should -Not -Contain 'DF020'
    }

    It 'suppresses skipped rules' {
        $file = New-Fixture -Content $script:Compliant.Replace('USER nonroot:nonroot', '')
        @(Get-DockerfileFinding -FilePath $file -Skip 'DF005' | ForEach-Object { $_.Rule }) | Should -Not -Contain 'DF005'
    }
}

Describe 'Image profiles' {
    It 'infers debug from the file name and relaxes labels and provenance' {
        $content = $script:Compliant.Replace('org.opencontainers.image.licenses=', 'org.example.licenses=').Replace('ARG GITHUB_RUN_ID=0', '')
        $file = New-Fixture -Content $content -Name 'Dockerfile.Debug'
        $findings = @(Get-DockerfileFinding -FilePath $file)
        @($findings | ForEach-Object { $_.Rule }) | Should -Not -Contain 'DF015'
        @($findings | ForEach-Object { $_.Rule }) | Should -Not -Contain 'DF014'
        (Resolve-ImageProfile -FilePath $file -Model (Read-DockerfileModel -Line @(Get-Content $file)) -Requested 'auto') | Should -Be 'debug'
    }

    It 'reads the profile from the header comment' {
        $content = $script:Compliant.Replace('# Example image', "# Profile: single-arch`n# Example image").Replace('FROM gcr.io', 'FROM --platform=linux/arm64 gcr.io').Replace('FROM --platform=$BUILDPLATFORM golang', 'FROM golang')
        $rules = Get-Rule -Content $content
        $rules | Should -Not -Contain 'DF003'
        $rules | Should -Not -Contain 'DF004'
    }

    It 'lets vendor images omit provenance but still requires labels' {
        $content = $script:Compliant.Replace('ARG GITHUB_RUN_ID=0', '').Replace('org.opencontainers.image.licenses=', 'org.example.licenses=')
        $rules = Get-Rule -Content $content -ImageProfile 'vendor'
        $rules | Should -Not -Contain 'DF014'
        $rules | Should -Contain 'DF015'
    }

    It 'applies only security, pinning and non-root rules to samples' {
        $rules = Get-Rule -Content "FROM rust`nRUN cargo build --release`nCMD ./target/release/app" -ImageProfile 'sample'
        $rules | Should -Contain 'DF002'
        $rules | Should -Contain 'DF005'
        $rules | Should -Not -Contain 'DF001'
        $rules | Should -Not -Contain 'DF006'
    }
}

Describe 'Stage inheritance and workload shapes' {
    BeforeAll {
        $script:Layered = $script:Compliant.Replace('FROM gcr.io/distroless/static-debian13:nonroot AS final', 'FROM debian:13-slim AS runtime').Replace(
            'ENTRYPOINT ["/app/app"]',
            "ENTRYPOINT [`"/app/app`"]`n`nFROM runtime AS debug`nUSER root`nRUN apt-get update && apt-get install -y --no-install-recommends curl && rm -rf /var/lib/apt/lists/*`nUSER nonroot:nonroot`n`nFROM runtime AS final")
    }

    It 'lets final inherit USER, provenance and labels from its runtime stage' {
        $rules = Get-Rule -Content $script:Layered
        $rules | Should -Not -Contain 'DF005'
        $rules | Should -Not -Contain 'DF014'
        $rules | Should -Not -Contain 'DF015'
    }

    It 'does not require runtime-side stages to be pinned to BUILDPLATFORM' {
        Get-Rule -Content $script:Layered | Should -Not -Contain 'DF004'
    }

    It 'still reports a root USER inherited from the runtime stage' {
        Get-Rule -Content $script:Layered.Replace("USER nonroot:nonroot`nENTRYPOINT", "USER root`nENTRYPOINT") | Should -Contain 'DF005'
    }

    It 'returns the chain base first' {
        $model = Read-DockerfileModel -Line @($script:Layered -split "`n")
        $chain = @(Get-StageChain -Stage $model.Stages[-1] -Stages $model.Stages)
        @($chain | ForEach-Object { $_.Name }) | Should -Be @('runtime', 'final')
    }

    It 'reads the workload shape from the header and defaults to service' {
        (Resolve-WorkloadShape -Model (Read-DockerfileModel -Line @($script:Compliant -split "`n"))) | Should -Be 'service'
        $tool = $script:Compliant.Replace('# Example image', "# Shape: tool`n# Example image")
        (Resolve-WorkloadShape -Model (Read-DockerfileModel -Line @($tool -split "`n"))) | Should -Be 'tool'
    }

    It 'reports EXPOSE in a <Shape> image' -TestCases @(@{ Shape = 'tool' }, @{ Shape = 'job' }) {
        param($Shape)

        $content = $script:Compliant.Replace('# Example image', "# Shape: $Shape`n# Example image").Replace('USER nonroot:nonroot', "EXPOSE 8080`nUSER nonroot:nonroot")
        Get-Rule -Content $content | Should -Contain 'DF024'
    }

    It 'accepts EXPOSE in a service image' {
        Get-Rule -Content $script:Compliant.Replace('USER nonroot:nonroot', "EXPOSE 8080`nUSER nonroot:nonroot") | Should -Not -Contain 'DF024'
    }
}

Describe 'Find-Dockerfile' {
    It 'finds Dockerfile variants and skips dev container, deps and ignore files' {
        $root = Join-Path $TestDrive 'discovery'
        foreach ($relative in @('Dockerfile', 'Dockerfile.Debug', 'Dockerfile.Debug.dockerignore', 'src/api/Dockerfile', 'tools/build.dockerfile', '.devcontainer/Dockerfile', 'deps/sibling/Dockerfile')) {
            $target = Join-Path $root $relative
            New-Item -ItemType Directory -Path (Split-Path $target) -Force | Out-Null
            Set-Content -LiteralPath $target -Value 'FROM scratch'
        }

        $found = @(Find-Dockerfile -Path $root | ForEach-Object { [IO.Path]::GetRelativePath($root, $_).Replace('\', '/') })
        $found | Should -Be @('Dockerfile', 'Dockerfile.Debug', 'src/api/Dockerfile', 'tools/build.dockerfile')
    }

    It 'rejects a missing path' {
        { Find-Dockerfile -Path (Join-Path $TestDrive 'missing') } | Should -Throw '*does not exist*'
    }
}

Describe 'Script exit codes' {
    It 'exits <Expected> with FailOn <FailOn>' -TestCases @(
        @{ FailOn = 'error'; Mutate = $false; Expected = 0 }
        @{ FailOn = 'error'; Mutate = $true; Expected = 2 }
        @{ FailOn = 'never'; Mutate = $true; Expected = 0 }
    ) {
        param($FailOn, $Mutate, $Expected)

        $content = if ($Mutate) { $script:Compliant.Replace('USER nonroot:nonroot', '') } else { $script:Compliant }
        $file = New-Fixture -Content $content
        $null = & pwsh -NoProfile -File $scriptPath -Path $file -FailOn $FailOn 6>&1
        $LASTEXITCODE | Should -Be $Expected
    }

    It 'exits 1 when the path does not exist' {
        $null = & pwsh -NoProfile -File $scriptPath -Path (Join-Path $TestDrive 'missing') 2>&1
        $LASTEXITCODE | Should -Be 1
    }
}
