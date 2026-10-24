# Container Workflow Caller Setup

Use this example to add thin entry points to an existing application repository. It does not
authorize builds, registry publication, deployment, commits or pushes.

## Install the Entry Points

Render the [PowerShell shim](../templates/entrypoint.ps1.tmpl) and
[Bash launcher](../templates/entrypoint.sh.tmpl) twice:

| Destination | `{{IMPLEMENTATION}}` | `{{ENTRYPOINT}}` |
| --- | --- | --- |
| `build.ps1`, `build.sh` | `Build` | `build` |
| `deploy.ps1`, `deploy.sh` | `Deploy` | `deploy` |

There must be no remaining tokens. The PowerShell shims deliberately have no parameter block:
they forward the implementation's switches unchanged, including `-WhatIf`, without maintaining a
second parameter contract. They resolve the caller from their own location, not the shell's current
directory, prefer the user-profile skill link, and propagate the implementation's exit code.
The Bash launchers require `pwsh` and replace themselves with it.

Preserve existing caller-specific behavior; do not overwrite a custom shim blindly. Set executable
mode on Bash launchers on platforms that require it.

## Configure Local Deployment

Copy [the data example](../templates/deploy.local.psd1.example) into the caller's root as
`deploy.local.psd1`. Add `deploy.local.psd1` and `deps/` to that repository's `.gitignore` before
populating it. Keep a sanitized `.psd1.example` tracked in the caller when it documents its contract.

Replace the three required values: `ManifestRepo` is an existing absolute local GitOps checkout,
`ManifestPath` is relative to that checkout, and `PodAnnotationName` is the intended rollout
annotation key. The checkout must be clean with an upstream branch before a real deployment.
Do not create another checkout implicitly.

The remaining keys map to the implementation's parameters:

* Image identity, tag, platforms and deployment name select the artifact and rollout identity.
* `NoCommit = $true` deliberately leaves manifest edits uncommitted. It does **not** disable image
  publication or other deployment mutations. Explicit command-line parameters override this file.
* Enable `Chart` only with `ChartPath` and `ChartRepository` populated. `ChartPath` is relative to
  the application root; `ChartRepository` is the OCI namespace/repository used by the script.
* Populate `MigrationProject` and, when needed, `MigrationContext` only for an existing EF check.
  `MigrationConnectionStringEnvironmentVariable` names the variable the application reads.
  Never store `MigrationConnectionString` in this plaintext file. Acquire it from an approved
  secret provider in the invoking process and pass it in-process without printing it.
* `RepositoryRoot` comes from the shim. `DeployConfigPath` selects an alternative data file on the
  command line. Extra build options are command-line arguments, not additional data-file keys.

## Invocation and Side Effects

Run from the application root: some underlying tooling resolves local tools/configuration there.
Start with the preview, using PowerShell 7.4 or later:

```powershell
./deploy.ps1 -WhatIf
```

Preview still requires valid settings, an existing manifest and `yq`. It validates prerequisites,
but does not prove registry credentials, the eventual build, chart publication or rollout.

| Invocation | Effects after authorization |
| --- | --- |
| `./build.ps1 -Configuration Release -Load` | Builds and loads a host-platform image; does not publish or deploy |
| `./build.ps1 -Push` | Publishes an image; does not patch GitOps |
| `./deploy.ps1 -NoCommit` | Refreshes the GitOps checkout, builds/pushes a Debug image, patches the manifest; leaves edits uncommitted |
| `./deploy.ps1 -SkipBuild -NoCommit` | Still refreshes and patches GitOps using the registry digest of an existing tag |
| `./deploy.ps1 -Chart -NoCommit` | Additionally packages/publishes a chart and updates its revision |
| `./deploy.ps1 -NoCommit:$false` | Additionally commits and pushes GitOps; requires explicit authorization for both |

`-SkipBuild` is not a dry run and `-NoCommit` is not a no-publication switch. A real deployment
also removes the generated caller `deps/` directory during cleanup. The script can only patch
the supported `Application`/`ApplicationSet` single-source shapes and the shared chart's
`_shared` image contract; validate those prerequisites rather than assuming arbitrary manifests work.

## Check the Result

Before real execution, parse the rendered shims, import the data example with
`Import-PowerShellDataFile`, and exercise argument/exit forwarding with a synthetic implementation.
After authorized deployment, verify the exact changed manifest, digest-qualified image tag,
chart revision when selected, and separate commit/push state. Static tests do not establish that
Argo CD reconciled the change or that the application became ready.

Wait for the expected digest in each workload before trusting rollout status. Probe the configured
health endpoints using their actual plain-text or JSON response contract, and check restart counts
and sustained application errors as well as readiness. Strip ANSI formatting before classifying log
severity; summarize failures without exposing dynamic service-user data. When network policy blocks
the API-server HTTP proxy, use a localhost-only port-forward rather than weakening isolation or
assuming a minimal runtime image contains a shell or HTTP client. A healthy probe is not proof that
event persistence or other business operations succeeded; verify representative progress separately.
Clean recent reconciliation windows do not explain earlier divergences: trace the affected lifecycle
through its authoritative source and durable journal before accepting it. Distinguish restore-only
consumers from session-owning publishers; rolling a publisher can require normal authentication even
when a consumer must never initiate login.
For expiring session/cache handoffs, observe dependent progress beyond the configured TTL within
one uninterrupted ownership run, including idle workloads. Restart or reauthentication resets the
measurement window. Initial post-login success does not prove renewal; verify that the authorized
owner maintains the handoff without relying on unrelated traffic or repeated reauthentication.
