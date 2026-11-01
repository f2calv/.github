# Skill Catalogue

Each skill is a self-contained workflow under [.github/skills](../.github/skills/). Copilot loads a
skill when a request matches its description, or when invoked directly, such as `/docs-readme`.
Follow the linked `SKILL.md` for prerequisites, safety gates and detailed commands. The Version
column shows each skill's current version; `Set-SkillVersion.ps1` updates it and the pull request
gate rejects a stale or missing row.

## Documentation and Repository Hygiene

| Skill | Version | Use it for |
| --- | --- | --- |
| [README authoring](../.github/skills/docs-readme/SKILL.md) | `1.0.1` | Consumer-focused documentation for public and private applications, libraries, Actions, workflows and infrastructure |
| [ADR authoring](../.github/skills/docs-adr/SKILL.md) | `1.0.2` | Evidence-backed architecture decisions kept current across sessions, with optional GitHub issues labelled adr |
| [Architecture diagrams](../.github/skills/docs-architecture-diagrams/SKILL.md) | `1.0.0` | Top-down Mermaid views from system context to components, runtime scenarios, flows and dependency graphs, with README versus `docs/` placement |
| [Repository baseline](../.github/skills/github-repository-baseline/SKILL.md) | `1.1.0` | Auditing and reconciling GitHub settings, default-branch rules and analysis requirements |
| [Repository privacy](../.github/skills/repository-privacy/SKILL.md) | `1.1.0` | Checking public changes for personal data, credentials and private-system details; stripping agent attribution before a push |
| [Issues and pull requests](../.github/skills/github-issues-and-pull-requests/SKILL.md) | `1.0.2` | Issue quality, pull request descriptions, review findings and merge readiness |
| [Archive repository](../.github/skills/github-repository-archive/SKILL.md) | `1.0.0` | Explicitly requested retirement, archiving and optional local cleanup |
| [Summarize for PR](../.github/skills/repository-pr-summary/SKILL.md) | `1.0.0` | An explicitly requested temporary branch-change summary for review |
| [Dependabot management](../.github/skills/github-dependabot/SKILL.md) | `1.0.1` | Coverage, grouping and troubleshooting across dependency ecosystems |
| [GitHub Actions workflows](../.github/skills/github-actions-workflows/SKILL.md) | `1.0.0` | Composing CI from shared reusable workflows, starter templates and releasing shared-workflow changes safely |

## Tooling and Agent Setup

| Skill | Version | Use it for |
| --- | --- | --- |
| [Pre-commit management](../.github/skills/tooling-pre-commit/SKILL.md) | `1.0.1` | Configured lint hooks, pinned runtimes and native or Docker execution |
| [EditorConfig management](../.github/skills/tooling-editorconfig/SKILL.md) | `1.0.0` | Shared formatting profiles, analyzer rules and drift |
| [Local overrides](../.github/skills/tooling-local-overrides/SKILL.md) | `1.0.1` | Ignore precedence and local-only Copilot instructions, skills and tool configuration |
| [REST Client requests](../.github/skills/tooling-rest-client/SKILL.md) | `1.0.0` | Structured HTTP requests, authentication examples and secret handling |
| [Dev Containers](../.github/skills/containers-devcontainer/SKILL.md) | `1.0.0` | Development images, Features, lifecycle commands and editor integration |
| [Spec Kit bootstrap](../.github/skills/spec-kit-bootstrap/SKILL.md) | `1.0.0` | Spec-driven development setup for new or existing repositories, with a Specify-ready Dev Container |
| [Spec Kit session tutor](../.github/skills/spec-kit-guide/SKILL.md) | `1.0.0` | Where you are in a feature, the last observed command, recommended next actions and optional-stage shortcuts |
| [Skill library](../.github/skills/skill-library/SKILL.md) | `1.1.1` | Skill sidecars, version bumps, Spec Kit extension releases and `/speckit-skill-library` installation |

## Containers, Kubernetes and Infrastructure

| Skill | Version | Use it for |
| --- | --- | --- |
| [Container images](../.github/skills/containers-images/SKILL.md) | `1.0.0` | Dockerfile authoring, image profiles, build strategy and static auditing |
| [Docker Compose](../.github/skills/containers-docker-compose/SKILL.md) | `1.0.3` | Local stacks, profiles, readiness, storage/network isolation, troubleshooting and workspace-wide audits |
| [Container workflows](../.github/skills/containers-workflows/SKILL.md) | `1.0.1` | Shared local container build and GitOps deployment scripts |
| [Helm charts](../.github/skills/kubernetes-helm/SKILL.md) | `1.0.1` | Chart contracts, values, dependencies, documentation and OCI packaging |
| [File to ConfigMap](../.github/skills/kubernetes-configmap-sync/SKILL.md) | `1.0.0` | Reviewed non-secret JSON, XML or UTF-8 text synchronized into one existing GitOps ConfigMap key |
| [GitOps repository structure](../.github/skills/gitops-repository-structure/SKILL.md) | `1.0.0` | Argo CD Application discovery, ownership and stateful migrations |
| [NGINX ingress migration](../.github/skills/kubernetes-nginx-migration/SKILL.md) | `1.0.0` | Parallel controller rollout, compatibility mapping, cutover and rollback |
| [Terraform IaC](../.github/skills/terraform-infrastructure/SKILL.md) | `1.0.0` | Onion-layered deployment roots, local/private child modules, mature external module repositories and safe provisioning/retirement |
| [OIDC app registration](../.github/skills/identity-oidc-registration/SKILL.md) | `1.0.2` | Entra ID and Google Workspace sign-in registrations, secrets, proxy callbacks and public exposure |
| [UniFi network management](../.github/skills/network-unifi/SKILL.md) | `1.0.0` | Network discovery, VLANs, host networking and performance diagnostics |

## Architecture Patterns

| Skill | Version | Use it for |
| --- | --- | --- |
| [Modular monolith](../.github/skills/patterns-modular-monolith/SKILL.md) | `1.0.2` | One image with configured API/worker roles, module composition, endpoint gating and supervised lifecycles |
| [Ports and adapters](../.github/skills/patterns-ports-and-adapters/SKILL.md) | `1.0.2` | Application-owned integration contracts, provider substitution, dependency inversion and shared behavioral tests |
| [Architecture review](../.github/skills/patterns-architecture-review/SKILL.md) | `1.0.0` | Evidence-backed architecture smells with proportionate fixes, and realigning code to its components view |

## .NET

| Skill | Version | Use it for |
| --- | --- | --- |
| [AppHost bootstrapping](../.github/skills/dotnet-apphost/SKILL.md) | `1.0.2` | Thin entry points, configuration/logging ordering, feature registration, endpoints, health, shutdown and process results |
| [Dependency injection](../.github/skills/dotnet-dependency-injection/SKILL.md) | `1.0.2` | Lifetimes, provider factories, shared-instance aliases, scopes, disposal and composition validation |
| [Polymorphic configuration](../.github/skills/dotnet-polymorphic-configuration/SKILL.md) | `1.0.1` | Discriminator-based DTO graphs, merged configuration bridges and derived-type startup validation |
| [Background pipelines](../.github/skills/dotnet-background-pipelines/SKILL.md) | `1.0.2` | Bounded channels, backpressure, delivery boundaries, fault supervision and shutdown draining |
| [Cron scheduling](../.github/skills/dotnet-cron-scheduling/SKILL.md) | `1.0.2` | Cronos expressions, time zones, missed occurrences, non-overlap and injected clocks |
| [Leadership election](../.github/skills/dotnet-leadership-election/SKILL.md) | `1.0.2` | Redlock-backed leader lifecycles, safe failover, shared caching integration and replica-aware validation |
| [HTTP integrations](../.github/skills/dotnet-http-integrations/SKILL.md) | `1.0.2` | Outbound clients, authentication, retry safety, timeouts, streaming and fake-handler tests |
| [Web API](../.github/skills/dotnet-webapi/SKILL.md) | `1.0.3` | Thin controllers, TypedResults, DTO services and verified HTTP/OpenAPI contracts |
| [gRPC](../.github/skills/dotnet-grpc/SKILL.md) | `1.0.1` | Protobuf contracts, HTTP/2 clients and servers, stream recovery, acknowledgements and Kubernetes operations |
| [MCP servers](../.github/skills/dotnet-mcp/SKILL.md) | `1.0.3` | Read-only Streamable HTTP tools, registration, contracts and protocol validation |
| [Blazor frontend](../.github/skills/dotnet-blazor/SKILL.md) | `1.0.3` | Render modes, co-hosted WebAssembly clients, cookie authentication and multi-replica frontends |
| [CLI applications](../.github/skills/dotnet-cli/SKILL.md) | `1.0.2` | Command parsing, help/version isolation, configuration precedence, finite jobs and verified process outcomes |
| [EF Core data access](../.github/skills/dotnet-efcore/SKILL.md) | `1.0.3` | Contexts, mappings, query performance, PostgreSQL, transactions, concurrency and safe schema migrations |
| [Redis data access](../.github/skills/dotnet-redis/SKILL.md) | `1.0.2` | Key roles, cache-aside reads, expiry, invalidation, streams and endpoint placement |
| [Exceptions](../.github/skills/dotnet-exceptions/SKILL.md) | `1.0.0` | Throw-site audits and area-specific domain exception types |
| [Cleanup](../.github/skills/dotnet-cleanup/SKILL.md) | `1.0.2` | Source layout, naming and analyzer-driven cleanup |
| [Performance](../.github/skills/dotnet-performance/SKILL.md) | `1.0.0` | Measured hot-path, allocation and parsing improvements |
| [Test platform](../.github/skills/dotnet-test-platform/SKILL.md) | `1.0.0` | Microsoft.Testing.Platform and xUnit v3 configuration and migration |
| [Upgrade](../.github/skills/dotnet-upgrade/SKILL.md) | `1.0.0` | Major-version and NuGet upgrades, release-note-driven improvements, deprecations and compatibility checks |
| [Release train](../.github/skills/dotnet-release-train/SKILL.md) | `1.1.0` | Dependency-ordered NuGet updates, releases and consumer propagation |
