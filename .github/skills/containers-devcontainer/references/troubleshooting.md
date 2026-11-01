# Troubleshooting

Diagnose a Dev Container that fails to start and map common symptoms to responses.

## Diagnose a Failed Start

When a configuration works on one workstation but not another, suspect the host before the
repository. Gather evidence before editing tracked files.

1. Read the newest Dev Containers extension log first. On Windows it is under
   `%APPDATA%\Code\logs\<session>\window<n>\exthost\ms-vscode-remote.remote-containers\`; use
   **Dev Containers: Show Container Log** on any platform. Search for `Error response from daemon`,
   `Command failed` and `Exit code`.
2. Compare the logged `docker run` arguments with the configuration. The extension adds its own
   mounts, such as the WSLg Wayland socket, the Git credential helper and the `vscode` volume; a
   failing mount that the repository does not declare points to host or extension settings.
3. Reproduce the failing argument alone with a throwaway container such as
   `docker run --rm --mount <failing-mount> alpine:3 true`, then remove any image pulled only for
   the test. A standalone failure proves the cause is independent of the repository image.
4. Check host state: `docker version`, `docker context ls`, `wsl -l -v`, the Docker Desktop WSL
   integration setting for each distribution and whether the relevant distribution is running.
5. Fix host-specific causes in host or user settings, not tracked repository files. Ask before
   changing a user setting that affects every Dev Container, and note that Settings Sync may carry
   it to other workstations.

| Symptom | Response |
| --- | --- |
| Feature fails after a base upgrade | Check distribution support and Feature options first |
| Docker cannot reach the host daemon | Verify Docker-outside-of-Docker and host socket support |
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
