# Report Label Workflow

A local reusable GitHub Actions workflow that validates a requested mode and returns a label for
downstream jobs. This is a synthetic source-only example; it does not generate a report or publish
an artifact.

## Usage

Copy [the workflow](./_report-label.yml.tmpl) to `.github/workflows/_report-label.yml` in the
consuming repository. The `.tmpl` file itself is not discovered or executed by GitHub.
Then call it from another workflow in that same repository:

```yaml
name: report-example

on:
  workflow_dispatch:

permissions: {}

jobs:
  label:
    uses: ./.github/workflows/_report-label.yml
    permissions: {}
    with:
      mode: detailed

  show:
    needs: label
    runs-on: ubuntu-24.04
    permissions: {}
    steps:
      - name: printf report label
        shell: bash
        env:
          REPORT_LABEL: ${{ needs.label.outputs.label }}
        run: printf '%s\n' "$REPORT_LABEL"
```

The downstream job prints `Detailed`. Omitting `mode` selects `Summary`.
This local `uses:` form reads the workflow from the caller's commit; it is not a remote version pin.
Only advertise a cross-repository invocation after verifying a published source and immutable tag.

## Inputs

| Input | Type | Default | Contract |
| --- | --- | --- | --- |
| `mode` | string | `summary` | Exactly `summary` or `detailed`; other values, including an explicitly empty string, fail |
| `runs-on` | string | `ubuntu-24.04` | Runner label; an override must provide Bash |

## Outputs

| Output | Values | Source |
| --- | --- | --- |
| `label` | `Summary` or `Detailed` | Step output forwarded through the job and reusable-workflow output |

## Permissions and Secrets

No repository permissions or secrets are required. Both the caller and callee use `permissions: {}`.
Do not add `secrets: inherit` to this example: it has no secret consumer. It does not check out code,
access registries, or mutate remote resources.

The mode enters Bash through an environment variable, not interpolation into script text. The
script validates it against two exact values before writing a fixed single-line output.

## Validation

Local fixture tests execute the extracted Bash step for both valid modes and invalid inputs,
including a value containing shell syntax. They assert the output file and nonzero failure status.
They also check the declared input defaults, permissions and output links.
This does not prove GitHub runner scheduling or workflow execution; those require a separately
authorized run in the consuming repository.
