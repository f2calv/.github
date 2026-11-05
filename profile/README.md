# Open-source .NET, AI and DevOps Projects

Tools for .NET, AI agents, CI/CD and cloud-to-edge development.
**If you find a repository useful, please give it a :star:!**

> [!WARNING]
> **All repositories listed here are unsupported works in progress.**
> Use at your own risk.

## Shared AI Skills and GitHub Copilot Instructions

:books: **[.github](https://github.com/f2calv/.github)**: reusable Copilot instructions and
[agent skills](https://github.com/f2calv/.github/blob/main/docs/skills.md) for development and infrastructure.
Use with Copilot, Spec Kit extensions or Agent Plugins.

## AI Agents and Applications

- :house: **[SmartHaus](https://github.com/f2calv/SmartHaus)**: edge smart-home and IoT integrations with HTTP and Model Context Protocol (MCP) tools.
- :robot: **[agentizr](https://github.com/f2calv/agentizr)**: multi-tenant .NET agent runtime for OpenAI-compatible servers, Azure OpenAI and Ollama.
- :student: **[tutorizr](https://github.com/f2calv/tutorizr)**: Signal-group tutor host with German-language learner tools and an external agent runtime.

## Signal Messenger Integration

:speech_balloon: **[signalizr](https://github.com/f2calv/signalizr)**: Signal Messenger gateway
with named-group REST messaging, durable gRPC subscriptions and MCP tools.

## GitHub Actions and Workflows

- **[gha-workflows](https://github.com/f2calv/gha-workflows)**: multi-language CI/CD, publishing, Terraform and GitOps.
- **[gha-release-versioning](https://github.com/f2calv/gha-release-versioning)**: semantic versioning, tags and releases.
- [gha-dotnet-nuget](https://github.com/f2calv/gha-dotnet-nuget): .NET builds, tests, coverage and NuGet publishing.
- [gha-gitops-manifest-update](https://github.com/f2calv/gha-gitops-manifest-update): Kubernetes image updates and Helm rendering.
- [gha-check-release-exists](https://github.com/f2calv/gha-check-release-exists): release-tag checks before publishing.

## Multi-Architecture Docker Examples

The same worker in **[C#/.NET](https://github.com/f2calv/multi-arch-container-dotnet)**,
**[Go](https://github.com/f2calv/multi-arch-container-go)**,
**[Rust](https://github.com/f2calv/multi-arch-container-rust)** and
**[Python](https://github.com/f2calv/multi-arch-container-python)**:
one Dockerfile per language, targeting Linux AMD64, ARM64 and ARMv7 with Docker Buildx.

## Kubernetes Helm Charts

:ship: **[helm-charts](https://github.com/f2calv/helm-charts)**: public OCI charts for
reusable workloads, jobs, KEDA autoscaling and persistent signal-cli deployments.

## Azure DevOps Pipeline Migration

:arrows_counterclockwise: **[yamlizr](https://github.com/f2calv/yamlizr)**: convert Azure DevOps
Classic pipelines to YAML, with optional GitHub Actions conversion. Review and test generated output.

## .NET Libraries and API Integrations

- **[CasCap.Common](https://github.com/f2calv/CasCap.Common)**: caching, configuration, HTTP, serialization and hosting.
- [CasCap.Api.Azure](https://github.com/f2calv/CasCap.Api.Azure): Azure PaaS helpers.
- [CasCap.Api.GooglePhotos](https://github.com/f2calv/CasCap.Api.GooglePhotos): unofficial Google Photos API client.
- [CasCap.Api.SignalCli](https://github.com/f2calv/CasCap.Api.SignalCli): typed Signal clients with polling and WebSocket reception.
- [CasCap.Api.Voice](https://github.com/f2calv/CasCap.Api.Voice): speech-to-text and text-to-speech with local and Azure providers.
