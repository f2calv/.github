# Troubleshooting

Diagnose a Dev Container that fails to start and map common symptoms to responses.

## Diagnose a Failed Start

When a configuration works on one workstation but not another, suspect the host before the
repository. Gather evidence before editing tracked files.

1. Read the newest Dev Containers extension log first. On Windows it is under
   `%APPDATA%\Code\logs\<session>\window<n>\exthost\ms-vscode-remote.remote-containers\`; use
   **Dev Containers: Show Container Log** on any platform. Search for `Error response from daemon`,
   `Command failed` and `Exit code`.
2. Compare the logged container CLI/run arguments with the configuration. The extension adds its own
   mounts, such as the WSLg Wayland socket, the Git credential helper and the `vscode` volume; a
   failing mount that the repository does not declare points to host or extension settings.
3. Reproduce the failing argument alone with a throwaway container such as
   `docker run --rm --mount <failing-mount> alpine:3 true`, then remove any image pulled only for
   the test. A standalone failure proves the cause is independent of the repository image.
4. Check the selected engine's state using [container tooling](../../containers-tooling/SKILL.md).
   On Docker Desktop, inspect `docker version`, contexts, WSL integration and distribution state.
   On Podman, inspect its machine/connection/provider and configured Dev Containers CLI.
5. Fix host-specific causes in host or user settings, not tracked repository files. Ask before
   changing a user setting that affects every Dev Container, and note that Settings Sync may carry
   it to other workstations.

| Symptom | Response |
| --- | --- |
| Feature fails after a base upgrade | Check distribution support and Feature options first |
| Docker cannot reach the host daemon | Verify Docker-outside-of-Docker and host socket support |
| Rootless Podman socket is mounted but the non-root user gets permission denied | Compare socket ownership, `id` and `/proc/self/uid_map`; use the [rootless socket procedure](#rootless-podman-socket-access) |
| Host mount expands incorrectly | Use the correct Dev Container variable for the host platform |
| Hook works once but fails later | Move one-time work to post-create and make post-start idempotent |
| Startup changes tracked files | Remove update or generation commands from post-start |
| CI installs another tool version | Find and synchronize the authoritative version field |
| Host and container offer different extensions | Reconcile both lists and document justified exceptions |
| New file type lacks local tooling | Require execution evidence, then add one Feature or installer |
| Lockfile changes unexpectedly | Confirm the generator and repository lockfile policy |
| Files become root-owned | Restore the non-root user and use explicit `sudo` only where needed |
| Sibling repositories drift | Compare declared shared surfaces and update them together |
| `accessing specified distro mount service: stat /run/guest-services/distro-services/<distro>.sock` | The extension's automatic WSLg Wayland mount targets a WSL distribution without working Docker Desktop integration. Enable that distribution under Docker Desktop **Resources > WSL integration** and restart Docker Desktop, or set the user setting `"dev.containers.mountWaylandSocket": false` when the container runs no Linux GUI applications. Starting the distribution alone does not fix it |
| Works on one workstation only | Follow [Diagnose a Failed Start](#diagnose-a-failed-start) and compare host Docker, WSL and extension settings |

## Rootless Podman Socket Access

Socket access still requires explicit approval. A successful bind does not establish permission:
the same numeric UID inside and outside a user namespace can map to different machine users.

Inspect the remote user's `id`, the socket's owner/mode and `/proc/self/uid_map`. For a selected
Podman configuration, test `--userns=keep-id:uid=<remote-uid>,gid=<remote-gid>` through `runArgs`
when retaining the machine user's identity is appropriate. Keep this engine-specific choice in
a private host override rather than a shared Docker configuration. Retain `remoteUser` and recreate
only the task container to apply the namespace change.

Verify a non-root workspace write and an authenticated or local-socket request to the selected
engine API, checking its identity. API transport success does not prove an uninstalled Docker CLI
or Docker-outside-of-Docker Feature works. Never use world-writable socket permissions or a rootful
engine switch as an automatic fix.
