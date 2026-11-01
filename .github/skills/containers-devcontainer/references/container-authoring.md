# Container Authoring

Establish scope, choose the container model, author devcontainer.json and handle mounts and credentials.

## Establish Scope

1. Confirm the target repository or explicit workspace folders. Do not scan unrelated clones.
2. Inspect:
    * `.devcontainer/devcontainer.json`;
    * any devcontainer Dockerfile or Compose files;
    * lifecycle scripts under `.devcontainer/`;
    * `devcontainer-lock.json`, when tracked;
    * `.github/dependabot.yml`;
    * workflows, actions, scripts, and docs that read devcontainer fields;
    * `.vscode/extensions.json` and container-specific VS Code customizations;
    * added and renamed files in the working-tree and branch diff;
    * sibling repositories required to remain aligned.
3. Determine the visibility of the target and any precedent. For a public target, use official or
  public precedents and never carry private topology, mounts, registries, or internal tooling into
  tracked content.
4. Select the nearest compatible precedent by repository role and language.
5. Record every synchronization point before editing.

## Choose the Container Model

For a small tooling repository, use the [minimal tooling example](../examples/minimal-tooling.md)
to see image/Feature ownership, host/container extension parity and a non-installing post-create
script together. Select it only when its execution evidence matches the repository.

| Model | Use when |
| --- | --- |
| Official image | A language or base image plus Features is sufficient |
| Dockerfile | Native packages or image-layer customization are required |
| Docker Compose | Development needs additional services such as a database or emulator |

* Use the simplest model that satisfies the repository.
* Do not use Compose merely to run Docker commands from the container.
* Do not install one tool through the image, a Feature, and a lifecycle script.
* Keep the non-root user unless a concrete tool requires otherwise.
* Add capabilities, security options, or privileged mode only for a demonstrated runtime need.
* Require explicit approval before adding host sockets, sensitive mounts, capabilities, security
  overrides, or privileged mode. Docker socket access is effectively host-root access.

## Author `devcontainer.json`

Treat the file as JSON with comments and preserve its local style.

* Set a concise role-based `name`.
* Use exactly one of `image`, `build`, or the Compose properties.
* Reference Features by supported major version so Dependabot can update them.
* Pin concrete tool versions when CI or another script reads the Feature option as authoritative.
* Use `latest` only where reproducibility and environment parity do not matter.
* Disable unused tools in combined Features.
* Verify each Feature supports the selected base distribution. Distribution upgrades can require
  changed Feature options, especially for Docker client packages.
* Install only extensions needed for the repository's languages and workflows.
* Keep editor behavior in `.editorconfig` where possible; reserve VS Code settings for
  container-specific behavior.

## Handle Mounts and Credentials

* Prefer the default workspace mount. Bind a wider source root only for intentional sibling work.
* Use Dev Container variables such as `${localEnv:HOME}` and `${localEnv:USERPROFILE}` rather than
  literal home paths or user names.
* Mount kubeconfig, SSH, cloud CLI, or similar directories only when normal development needs them.
* Default to no credential mounts. When approved, mount the narrowest files possible, use
  least-privilege credentials, and do not start untrusted configurations with host credentials
  attached.
* Use read-only mounts where the container does not need to modify host files.
* Never copy credentials into images or commit secrets in environment settings, Compose files,
  Dockerfiles, examples, or lifecycle scripts.
* Document host prerequisites and fail clearly when a required mount is absent.
