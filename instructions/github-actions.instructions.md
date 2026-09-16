---
description: 'GitHub Actions workflow and composite-action conventions — naming, YAML style, security and GitVersion.'
applyTo: '.github/workflows/**,.github/actions/**,**/action.yml,**/action.yaml'
---

# GitHub Actions

## General

- Leave one blank line between steps within a job.
- Pin actions to the major version tag by default, such as `actions/checkout@v6`. Do not pin to a commit SHA and do not include minor or patch versions.
- Set `fetch-depth: 0` on `actions/checkout` whenever GitVersion is used, so it can read the full commit history. Use `fetch-depth: 1` only for lint-only workflows where history is unnecessary.
- Declare an explicit `permissions` block on every job and grant the minimum required, such as `contents: read`.

## Step Naming

- One-liners: when a step's `run` block is a single command, use that command, or a slightly abbreviated form of it, as the step `name` rather than a prose label — `name: npm install --global json5`, not `name: setup json5`.
- Multi-part setup: name each step with an `(N of M)` suffix, such as `name: setup yq (1 of 3)`.
- Matrix steps: include the matrix variables in the step name, such as `name: test (${{ matrix.os }}, ${{ matrix.config }})`.

## Naming Conventions

- Inputs and outputs: kebab-case, such as `image-registry`, `tag-override`, `git-user-name`.
- Environment variables: uppercase with underscores, such as `IMAGE_REGISTRY`, `TAG_OVERRIDE`.
- Secrets: uppercase with underscores, such as `GITHUB_TOKEN`, `REGISTRY_PASSWORD`.
- Never hardcode a secret value, a registry hostname or an owner/repository coordinate in a workflow. Pass them as secrets, repository variables or workflow inputs.

## Descriptions

- Keep every `description:` to one short line. State what the value is, not how or why to use it, and prefer `e.g. <example>` over prose describing the format.
- Apply the same rule to workflow inputs (`workflow_dispatch`, `workflow_call`) as to action inputs. `workflow_dispatch` descriptions render as field labels in the *Run workflow* dialog, where a long sentence wraps and makes the form look messy.
- Move rationale, caveats, deprecation notices and cross-references into a `#` comment directly above the input, not into the description string. Use the `#no-space-after-hash` comment style.
- Avoid multi-sentence descriptions — they bloat the file and make the input list hard to scan.
- Keeping `key: value` pairs out of descriptions also avoids the colon-space sequence that would otherwise force the whole scalar to be quoted.

  ```yaml
  #DEPRECATED, superseded by publisher-identity. Ignored when publisher-identity is set.
  PACKAGE_API_KEY:
    description: Long-lived package registry API key e.g. secrets.PACKAGE_API_KEY
    type: string
  ```

## YAML Style

- Two-space indentation for all workflow and action YAML files.
- Do not quote strings unless YAML requires it — values containing special characters, reserved words such as `true`, `false` or `null`, or strings that could be misinterpreted as another type.
- For `workflow_dispatch` string inputs that represent booleans, use quoted defaults such as `default: 'true'`.
- Use `|` for multi-line `run` scripts and `>` for flowing multi-line description text.
- One blank line between major YAML sections (`on:`, `env:`, `jobs:`). No blank lines within input or output lists.

## Reusability

- Reusability is a key requirement. Factor cross-cutting logic — build, test, lint, versioning, container and chart packaging, migration-drift checks — into reusable `workflow_call` workflows held in a dedicated shared-workflows repository, so every repository consumes one implementation.
- Keep logic inline, or in a repository-local reusable workflow, only when it is genuinely repository-specific and unlikely to be reused.
- Parameterise shared workflows with `inputs` (paths, project or context names, configuration, flags) so they stay repository-agnostic. A consumer passes specifics via `with:`.
- Filename convention differs by scope:
  - Shared (cross-repository): a non-underscore filename with an `_`-prefixed `name:`, for example the file `app-build.yml` declaring `name: _app-build`.
  - Local (same repository): an underscore-prefixed filename, such as `_publish-artifacts.yml`.

## Reusable Workflows

- Prefix local reusable workflow filenames with an underscore to distinguish them from top-level entry-point workflows.
- Same repository: `uses: ./.github/workflows/_filename.yml`.
- Cross-repository: `uses: owner/repo/.github/workflows/filename.yml@v1`, supplying the coordinate through configuration rather than hardcoding a private one.
- Prefer `secrets: inherit` unless there is a specific reason to restrict the secrets passed to the called workflow.

## Composite Actions

- Declare `shell: bash` explicitly on every `run` step — composite actions do not inherit a default shell.
- Reference scripts relative to the action root using `${{ github.action_path }}/.scripts/name.sh`.
- Extract sizeable or critical `run` logic into an external script under `.scripts/` rather than inlining it in the composite action YAML. An external script can be run and tested standalone, locally or from a test workflow, before a real Actions run ever exercises it; a `run: |` block embedded in YAML cannot.
- Keep genuinely trivial one-liners inline.

## Security

- Set workflow-level `permissions: {}` to deny everything, then grant only what each job requires.
- Skip bot-triggered runs conditionally, such as `if: github.actor != 'dependabot[bot]'`.
- Pass tokens via stdin for registry logins, such as `echo "$TOKEN" | docker login --password-stdin`.
- Force OCI registry, repository and tag values to lowercase, such as `${IMAGE_REGISTRY,,}`.

## Versioning

- Always set `fetch-depth: 0` on checkout when GitVersion is in use.
- The default configuration file is `GitVersion.yml` in the repository root.
- Prefer `semVer` for tags and releases; use `fullSemVer`, via the `version` output, for build versioning and pre-release identifiers.
- Publish each GitHub Actions release with an immutable `vMAJOR.MINOR.PATCH` tag, then move the floating `vMAJOR` alias to the same commit.
- Consumers should reference the floating major alias, such as `owner/action@v1`, to receive compatible fixes without changing workflow files.
- Move a major alias only after its immutable release tag succeeds. Never create floating minor, patch or pre-release aliases.
- Keep the reusable release workflow defaults `tag-prefix: v` and `move-major-tag: true` for GitHub Actions repositories. Non-Action repositories must override both settings to match their own release convention.
