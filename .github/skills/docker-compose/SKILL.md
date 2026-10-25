---
name: docker-compose
description: 'Create, update, audit or troubleshoot Docker Compose local development and demo stacks. Use for compose.yaml, docker-compose.yml, profiles, dependency readiness, networks, ports, volumes, secrets, interpolation, image compatibility, isolated test services and workspace-wide Compose reviews. Not for production deployment or Dockerfile-only authoring.'
argument-hint: '[create|update|audit|diagnose] [repository, file or workspace]'
user-invocable: true
---

# Docker Compose

Build a predictable local stack and review its effective behavior, not just valid YAML.
Keep default IDE dependencies, optional applications/demos and isolated test services deliberate.

## Authorities and Resources

- Read the target repository's notes and the central
  [Compose instructions](../../instructions/docker.compose.instructions.md). They own conventions;
  this skill owns the procedure. Read [image pinning](../../instructions/docker.instructions.md#base-images-and-pinning)
  when choosing image versions.
- Load [audit and validation](./references/audit-and-validation.md) for review criteria, safe commands,
  profile checks and troubleshooting.
- The [worked local stack](./examples/local-stack.md) explains the
  [Compose template](./assets/compose.yaml.tmpl), isolated test services and acceptance cases.
  The template is illustrative; select supported image versions before adopting it.
- Use [container images](../container-images/SKILL.md) for Dockerfiles/ignore files,
  [container workflows](../container-workflows/SKILL.md) for shared build/deploy scripts,
  [Dev Containers](../devcontainer/SKILL.md) for editor integration and
  [Dependabot](../dependabot-management/SKILL.md) for automated image updates.

## Modes and Safety

| Mode | Outcome |
| --- | --- |
| `create` | Write a local stack from verified application prerequisites and validate its contract |
| `update` | Change the requested surface, preserving state and intended defaults |
| `audit` | Read-only findings per file, with coverage and validation gaps; no automatic fixes |
| `diagnose` | Trace a specific configuration, readiness, network, mount or startup failure |

Do not start, stop, recreate or delete workloads as part of a static audit. Configuration checks do
not authorize builds, pulls, test execution, migrations or resets. Ask separately before runtime
smoke tests; confirm affected Docker context/project, services, ports and cleanup. Never use
`down --volumes`, pruning or shared-database resets without explicit data-deletion approval.
Keep private workspace identities and resolved secret values out of public artifacts.

## Workflow

### 1. Establish Scope and Invocation

1. Resolve explicit paths or actual VS Code workspace roots. For a workspace review, enumerate only
   those roots, deduplicate overlapping repositories and record roots with no Compose files.
   Do not infer scope from all sibling clones.
2. Find both `.yml`/`.yaml` variants of `compose*` and `docker-compose*`, including hidden tooling
   directories. Exclude generated/dependency outputs, but record excluded vendored/nested checkouts
   so omissions are visible. Also trace nonstandard filenames referenced by scripts or Dev Containers.
3. Inspect Git status and repository instructions before edits. Read every in-scope file and its
   callers: README commands, tasks, scripts, CI, Dev Containers, environment-file references and
   Dockerfile build inputs. Preserve unrelated edits.
4. Establish which files actually combine at runtime: explicit `-f` flags, `COMPOSE_FILE`, default
   overrides, includes/extends and project-directory/environment selection. In audit mode report
   layout deviations; do not consolidate files or rename services automatically.

### 2. Trace the Stack Contract

Record service purpose, default/profile membership, image/build context, platform, dependencies,
health/completion, restart policy, host/container endpoints, mounts and required inputs.
Trace application settings to the actual dependency addresses; a declared port or profile name is
not proof the application can connect.

Apply the reference's review matrix against the central instructions. Distinguish a convention
deviation from a demonstrated defect and an unverified runtime assumption.
Ask before changing topology, versions, port defaults, state locations or credential requirements.

### 3. Implement or Diagnose Precisely

Reuse existing stack/build helpers. Put optional heavy/source-built services behind deliberate
profiles; keep default dependencies usable from the IDE. Give test services independent data and
ports, including explicit host overrides where simultaneous workspace stacks could collide.

For moves/consolidation, update every caller and preserve effective relative paths, project
identity and volume ownership. Changing a project/service/volume name can select a new empty
database instead of migrating the old one. Do not remove existing data to make startup pass.
Keep troubleshooting evidence bounded and redacted; avoid dumping full container environments/logs.

### 4. Validate and Report

Use static source review and approved configuration checks first. Validate default, each supported
profile/combination and explicitly targeted one-shot paths; all-profile validation is not proof
that the default or an individual profile works. Check the expected service set as well as exit code.
Do not treat missing inputs, skipped checks or zero selected services as success.

When authorized, perform a bounded startup/readiness/connectivity check using an isolated project
and approved resources. Preserve existing workloads and data during cleanup.

For an audit report, include repository/file, line, finding category, impact, evidence, recommended
change and validation status. Summarize reviewed files, roots without files, exclusions and blockers.
Do not write a tracked audit report or modify audited stacks unless requested.

## Maintaining This Skill

Apply the shared [customization feedback loop](../../instructions/workflow.instructions.md#maintaining-conventions)
when this skill reveals reusable lessons; keep the convention itself in its existing authority.

- Incorporate verified profile, interpolation, storage or readiness lessons into the owning
  reference and extend the example/acceptance cases rather than accumulating incident-specific rules.
- Recheck Compose CLI flags, profile/dependency semantics and platform behavior when versions change.
- Refresh template images from publisher/platform evidence; distinguish configuration validation
  from successful pull, startup, protocol checks and application tests.
