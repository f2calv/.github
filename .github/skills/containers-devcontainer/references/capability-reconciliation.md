# Capability Reconciliation

Infer required Features and extensions from repository evidence and keep host and container extension lists in parity.

## Reconcile Repository Capabilities

Infer capabilities from what contributors must run locally, not from file extensions alone.

1. Inventory added and renamed files from the current Git diff, then scan the complete repository
   so one new file is interpreted in its existing context.
2. Find execution evidence in lifecycle scripts, developer commands, package manifests,
   `.pre-commit-config.yaml`, READMEs, and local validation scripts.
3. Classify each finding as:
   * editor support;
   * local runtime or CLI support;
   * CI-only support;
   * sensitive host access.
4. In `add`, `update`, `upgrade`, and `reconcile` modes, add safe missing Features and extensions in
   the same change. Ask before sensitive access. In `audit` mode, report only.
5. Never remove a Feature or extension automatically. Report apparently unused capabilities and
   require confirmation before removal.

Use this evidence matrix:

| Repository evidence | Editor action | Feature or local-tool action |
| --- | --- | --- |
| Locally executed `*.ps1` or a lifecycle command invoking `pwsh` | Add `ms-vscode.powershell` | Add `ghcr.io/devcontainers/features/powershell:2` |
| `*.Tests.ps1` or Pester module requirements | Add `ms-vscode.powershell` | Configure PowerShell `modules` with `Pester==<required-version>` |
| YAML authored in the repository | Add `redhat.vscode-yaml` | None unless local commands invoke `yq` |
| JSON authored in the repository | Use VS Code's built-in JSON support | None unless local commands invoke `jq` |
| `*.http` or `*.rest` request files | Add `humao.rest-client` | None; the extension executes requests |
| Local scripts or documented validation invoking `jq` or `yq` | No additional extension | Add `ghcr.io/eitsupi/devcontainer-features/jq-likes:2` |
| `*.tf` developed locally | Add `hashicorp.terraform` | Add the Terraform Feature and synchronize its version constraints |
| `Chart.yaml` or locally run Helm validation | Add the established Helm extension | Add or configure the Kubectl/Helm Feature |
| Dockerfile or Compose authoring | Add the established Containers extension | Add Docker access only when contributors run Docker inside the container |
| GitHub Actions authoring | Add `github.vscode-github-actions` | Add GitHub CLI only when local scripts or documented workflows invoke `gh` |
| Language manifest or source files | Add the established language extensions | Prefer the matching base image; use a language Feature only when needed |

Do not infer `jq-likes` from a YAML or JSON file alone. Do not infer local Features from commands
that run only in CI. A production Dockerfile does not by itself justify host Docker-socket access.

The official PowerShell Feature installs modules through a comma-separated `modules` option. There
is no separate official Pester Feature. Extract the required Pester version from `#Requires`, module
manifests, test runners, or CI, preserve any existing modules, and use an exact module version:

```jsonc
"ghcr.io/devcontainers/features/powershell:2": {
  "modules": "Pester==5.7.1"
}
```

Before adding a Feature, verify the image does not already provide the executable and that another
Feature or lifecycle command does not install it. Preserve established Feature IDs and option names
within aligned repository families.

## Synchronize VS Code Extensions

Treat `.vscode/extensions.json` as the canonical repository recommendation set for contributors
working on the host. Mirror its compatible `recommendations` set in
`customizations.vscode.extensions` so the same extensions are installed inside the Dev Container.
This duplication is deliberate: workspace recommendations suggest extensions, while Dev Container
customizations install them in the remote environment.

* When adding a shared extension, update both files in the same change.
* Compare extension IDs case-insensitively as sets. Preserve the repository's established grouping
  and comments; order alone is not drift.
* Validate every recommended extension ID against the current VS Code Marketplace. Confirm that it
  still exists, supports the required extension host and is not formally deprecated or replaced.
* Inspect `extensionPack` and `extensionDependencies` metadata before listing related extensions.
  Recommend the owning extension once; do not explicitly list extensions it installs automatically.
* Treat a compatibility pack, an abandoned overlapping extension or a broad product pack as a
  migration candidate even when the Marketplace has not formally deprecated it. Verify the
  publisher's current replacement guidance before changing IDs.
* Prefer the current direct extension over a compatibility extension pack. Use
  `ms-azuretools.vscode-containers` rather than the legacy `ms-azuretools.vscode-docker` pack.
* For modern .NET repositories, recommend `ms-dotnettools.csdevkit`; it installs
  `ms-dotnettools.csharp` automatically, so do not list both.
* For Terraform repositories, use `hashicorp.terraform` as the language, formatter and MCP provider.
  Do not also recommend overlapping syntax-only Terraform or HCL extensions unless the repository
  has a demonstrated file type or capability that the HashiCorp extension does not support.
* Avoid broad cloud extension packs when only one service integration is required. Recommend the
  specific extension so unrelated services, including unused database providers, are not installed.
* If `.vscode/extensions.json` is absent, create it when the container declares extensions that are
  also useful outside the container.
* Verify an extension ID exists and supports the required local or remote extension host before
  adding it.
* Do not copy `unwantedRecommendations` into the Dev Container extension list.
* Allow host-only or container-only extensions only for a demonstrated compatibility or execution
  reason. Document the exception beside the relevant list and report it during reconciliation.
* Do not add an extension only because it is personally preferred. Recommendations describe the
  repository's supported workflows.

When an extension is supplied automatically by a Feature, still include it in both explicit lists
when host/container parity is required. Explicit lists make drift reviewable and do not depend on a
Feature's implicit customization remaining unchanged.
