# Minimal PowerShell Tooling Dev Container

Use this example for a repository whose contributors run PowerShell/Pester locally and author
JSON/YAML. It is not a universal application image: language SDKs, Docker access and infrastructure
clients are intentionally absent. Prefer the appropriate language image when those are required.

## Copy the Matching Files

| Source | Destination in the consuming repository |
| --- | --- |
| [Container configuration](../templates/devcontainer.json) | `.devcontainer/devcontainer.json` |
| [Host extension recommendations](../templates/extensions.json) | `.vscode/extensions.json` |
| [Tool-version script](../templates/Show-ToolVersions.ps1.tmpl) | `.devcontainer/Show-ToolVersions.ps1` |

The container configuration is JSONC. Preserve its comments and merge existing extension
recommendations instead of replacing a repository's established set.

## One Installation Owner per Tool

| Capability | Owner | Not another installation path |
| --- | --- | --- |
| Debian environment and non-root `vscode` user | Official base image | No custom Dockerfile or startup package upgrade |
| PowerShell 7.4 release line | Official PowerShell Feature major 2 | No second PowerShell Feature or lifecycle installer |
| Pester 5.7.1 | The same Feature's `modules` option | No `Install-Module` in post-create |
| Tool verification | Post-create script | Imports the existing module and prints versions; does not execute tests |
| PowerShell, JSON and YAML editor support | Explicit extension lists | No extra language-runtime installation solely for an editor extension |

The image/distribution and tool versions are a concrete example, not a permanent fleet baseline.
Recheck publisher support and repository CI requirements before adoption. The PowerShell Feature's
`version` selects the 7.4 line, not an exact patch. Its `modules` option pins Pester independently.
If the image already supplies PowerShell, reconcile ownership rather than installing it again.

The [official Feature metadata](https://github.com/devcontainers/features/blob/main/src/powershell/devcontainer-feature.json)
defines the option names and its own lifecycle customization. `preserveHistory: false` disables
history preservation; the Feature may still declare its own named volume. That is not a host
credential bind mount. Inspect resolved Feature metadata before approving any sensitive host access.

## Lifecycle and Editor Behavior

Only `postCreateCommand` is set: it runs once after creation, from the workspace root. No dependency
restoration is needed in this tooling-only example. A repository that needs restoration should
add its existing restore script at the appropriate lifecycle stage, not an update command.
There is no post-start or post-attach mutation, automatic authentication, test execution or Git-hook
installation. An absent Pester version fails post-create explicitly instead of being installed silently.

The host recommendations and container extensions are identical as case-insensitive sets.
PowerShell may also be suggested by the Feature; explicit parity is deliberate, not a second
installation of the runtime. Keep formatting policy in `.editorconfig` and preserve the shared
Prettier/Markdown formatter boundaries; this example does not impose personal editor settings.

No host socket, credential directory, wider source tree, elevated capability or privileged mode is
requested. Use the default workspace mount. Extra access needs separate approval.

## Dependabot and Locking

Merge a `devcontainers` updater at `/` into the consuming repository's existing configuration
when it is absent:

```yaml
- package-ecosystem: devcontainers
  directory: /
  schedule:
    interval: weekly
```

This is an **updates-list fragment**, not a complete Dependabot configuration. It covers Features
and their lockfile, not a promise to update the direct `image` field. Review that image separately;
if a real Dockerfile or Compose file becomes necessary, add the corresponding updater for it.
Do not add an empty Dockerfile solely to justify an updater.

No lockfile is fabricated here. Preserve the repository's existing lock policy; regenerate tracked
lock data through its Dev Container implementation after Feature changes.

## Validate

1. Parse JSONC, resolve the lifecycle path, and verify each referenced Feature option.
2. Compare host/container extension sets and inspect the current Marketplace listings, extension
   dependencies and remote-host compatibility.
3. Parse the rendered PowerShell script and run it only in an approved fixture/environment.
   Confirm the exact required Pester version is imported and no installation or test command runs.
4. With separate build approval, rebuild the container, check tool versions inside it, and verify
   extension activation in the container's VS Code extension host.

Static checks and a host-side script run do not prove image build success or remote extension
activation. Report those dynamic checks as pending when no container build was authorized.
