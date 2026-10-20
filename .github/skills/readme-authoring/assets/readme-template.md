# README Master Template

Use this master outline for root and nested READMEs. It supplies section choices, not a mandatory
document length. Read the shared Markdown and Mermaid instructions for the rules governing content.

## Selection

Select all applicable delivery types, then remove irrelevant branches. The conditions below are
authoring annotations: remove them and replace every placeholder in the final README. Never leave
empty sections, placeholder tables or template instructions in a reader-facing document.

| Context | Select |
| --- | --- |
| Every README | Identity and summary; relevant usage or navigation; useful further-reading links |
| Published product | Verified destination links and suitable badges; license when applicable |
| Unpublished or source-only unit | Explicit availability and verified build/source-reference guidance; no speculative registry badge or install command |
| Collection | One catalogue linking to child READMEs and published artifacts |
| Application or CLI | Quick Start, Usage, Configuration; installation and platform requirements as needed |
| .NET or NuGet library | Installation, Usage or API, supported target frameworks; registration and configuration when exposed |
| Interchangeable providers or processing modes | Supported providers or modes, selection and enforcement boundaries; do not present declared-but-unimplemented options as capabilities |
| Native tools or external backends | Conditional Runtime Requirements; identify which capability needs each dependency and what the consuming host must supply |
| Testing companion package | Installation in consumer test projects, replacement example and limits of canned results; not the repository test-suite inventory |
| Dependency-only package | Explain the dependencies it bundles and underlying SDK setup; explicitly state when it exposes no wrapper API |
| Queue, event, stream or remote API client | Consumer-relevant delivery, failure, cancellation, timeout and rate-limit semantics; current upstream access restrictions |
| GitHub Action | Usage, Inputs, Outputs when present, required permissions and secrets; verified Marketplace link when published |
| Reusable workflows | Usage or Workflows catalogue, Inputs, Secrets, Permissions, Outputs when present; meaningful execution flow |
| Helm chart | Installation or Usage, Configuration, dependency graph when dependencies exist; chart catalogue for a chart repository |
| Terraform module | Usage, dependency graph when helpful, generator-owned interface reference |
| Container example | Quick Start or Run, Configuration, Platform Support when constrained |
| Meaningful relationships | A Mermaid diagram under the appropriate standard heading |
| Contributor setup differs from ordinary usage | Concise Development or Build and Test commands and prerequisites |
| Documentation index | Purpose and guide navigation; no product scaffolding unless it actually documents a product |
| Test project | Scope, prerequisites and execution; select required inventory and layout sections from the domain testing instructions, not package installation sections |

For mixed repositories, combine these choices rather than repeating shared sections for every type.
Retain specialized generator headings and consumer requirements from the domain's own authority.

## Master Outline

The outline is deliberately schematic. Replace prose instructions with evidence-based reader content,
not a paraphrase of the instructions. Optional sections are not a request to create new guides.

````markdown
# <Repository, package, chart or project identity>

<One or two sentences explaining the current purpose, value and intended audience.>

<!-- IF useful, verified badges exist: a compact linked badge row. -->

<!-- IF this is a collection: choose Packages, Projects, Workflows or Chart Catalogue. -->
## <Catalogue heading>

| Component | Purpose | Documentation | Published artifact |
| --- | --- | --- | --- |
| <Name> | <Current purpose> | <Child README link> | <Verified package, chart or listing link; version badge when useful> |

<!-- IF the reader can run or consume the product immediately. -->
## Quick Start

<Minimum prerequisites, shortest working command or example, and expected useful outcome.>

<!-- IF installation needs explanation beyond Quick Start; do not repeat the same commands. -->
## Installation

<Supported runtime or platform, current package/image/chart reference and installation command.>
<NuGet: use the actual package ID and state supported target frameworks.>
<Action: link its verified Marketplace listing when published; installation is normally a uses example.>
<Helm: give the supported repository or OCI installation path.>

<!-- IF the unit has a consumer-facing invocation or API. -->
## Usage

<A realistic minimal example with host context, required imports, configuration source and startup or resolution steps; common variations only where useful.>
<.NET library: show public APIs and required dependency-injection registration; apply the shared interface-source linking convention to contract descriptions.>
<Action: show a workflow step with its supported uses reference and required inputs.>
<Reusable workflow: show a caller job, required permissions and secret handoff.>
<Terraform: show a module call with a supported immutable source reference and required inputs.>

<!-- IF delivery guarantees, limits or remote-service policy materially affect correct usage. -->
## Behavior and Limits

<Explain acknowledgement/deletion timing, callback awaiting and batching side effects where relevant.>
<State timeout, retry and limiter scope, and current upstream access or token-lifecycle constraints.>
<Link to focused reference when the full contract is lengthy; do not invent delivery guarantees.>

<!-- IF capabilities require native tools or external services. -->
## Runtime Requirements

<Map each capability to its required executable, service, credential or host registration.>
<Keep optional dependencies conditional; distinguish what the package supplies from what the host installs or deploys.>

<!-- IF a hand-authored action/workflow contract exists; omit irrelevant subsections. -->
## Inputs

<Names, purpose, required status and defaults derived from the implementation.>

## Outputs

<Names, meaning and a short consumption example.>

## Permissions and Secrets

<Required permissions, credential acquisition and safe secret references; no real values.>

<!-- IF configuration is exposed and is not already covered by Inputs or a generated reference. -->
## Configuration

<Required and optional settings, meaningful defaults, constraints and where values are supplied.>
<For multiple providers or modes, identify supported selections and who enforces the policy.>
<Helm: explain common values and preserve generated values documentation if present.>

<!-- IF strongly typed configuration is exposed. -->
## Configuration Examples

<Minimal valid example, followed by more fully configured examples where useful.>
<Label complete configurations versus merge fragments and identify required host settings supplied elsewhere.>

<!-- IF a generator owns the public reference: insert its actual output and existing markers. -->
<Generator-owned requirements, providers, resources, inputs, outputs or values reference.>

<!-- IF compatibility or supported environments materially affect usage. -->
## Platform Support

<Verified runtime, operating-system, architecture or platform constraints not already stated.>

<!-- IF a diagram explains a meaningful relationship; choose the appropriate standard heading. -->
## <Dependency Graph, Data Flow, Service Architecture or another applicable diagram heading>

<Short explanation of scope and what the reader should learn.>

```mermaid
<Verified diagram using the shared Mermaid conventions.>
```

<!-- IF contributors need repository-specific setup beyond generic contribution guidance. -->
## Development

<Concise prerequisites and verified build, test or local-run commands.>
<Link to deeper guidance instead of explaining internal CI jobs or listing standard repository files.>

<!-- IF useful guides or inherited policies need an explicit navigation link. -->
## Documentation

<Purpose-labelled links to existing guides or applicable contribution, support and security guidance.>
<For a documentation index, make this navigation the main body instead of the product sections.>

<!-- IF a license applies. -->
## License

<License name and a link to its actual text.>
````

## Badge Patterns

These are Markdown syntax examples, not proof that a service or listing exists. Resolve identities,
visibility, publication and metric availability first. Omit any pattern that is not applicable.
Use absolute documentation links when a registry cannot resolve repository-relative links.

```markdown
[![NuGet version](https://img.shields.io/nuget/v/PACKAGE_ID)](https://www.nuget.org/packages/PACKAGE_ID)
[![GitHub Marketplace](https://img.shields.io/badge/Marketplace-Action-blue)](https://github.com/marketplace/actions/LISTING_SLUG)
[![CI status](https://github.com/OWNER/REPOSITORY/actions/workflows/WORKFLOW_FILE/badge.svg?branch=BRANCH)](https://github.com/OWNER/REPOSITORY/actions/workflows/WORKFLOW_FILE)
[![SonarQube coverage](https://sonarcloud.io/api/project_badges/measure?project=PROJECT_KEY&metric=coverage)](https://sonarcloud.io/component_measures?id=PROJECT_KEY&metric=coverage&view=list)
[![SonarQube Quality Gate](https://sonarcloud.io/api/project_badges/measure?project=PROJECT_KEY&metric=alert_status)](https://sonarcloud.io/dashboard?id=PROJECT_KEY)
```

The Marketplace badge identifies a destination; it does not display a live release version.
The analysis examples target SonarQube Cloud. For another SonarQube deployment, use its supported,
verified badge and project links only when safe and accessible; do not invent endpoints or tokens.
Where the service supports branch selection, align it with the status being described. Do not
force branch parameters onto services that do not support them.
