# Container Tool Troubleshooting

Trace the selected host/toolchain before changing tracked application configuration.

| Symptom | Evidence and response |
| --- | --- |
| CLI exists but engine is unreachable | Check the selected machine/context, endpoint and service state; do not automatically launch Desktop |
| A command reaches the wrong engine | Inspect process-local Docker environment/context overrides and Podman connection/provider selection |
| Compose disappears after Desktop removal | Install an independently approved Compose provider and verify its exact executable path/version |
| Registry access fails after Desktop removal | Inspect credential-helper references; authenticate through approved tooling without printing tokens or deleting unrelated credentials |
| Podman prompts for an image registry | Resolve the intended fully qualified image name; do not globally weaken registry policy |
| Registry/package TLS fails | Check proxy and trusted CA setup on host, machine, builder and image separately; never disable TLS verification |
| VPN blocks VM networking | Diagnose DNS/routes first; Podman WSL user-mode networking is an opt-in change affecting other WSL distributions |
| Windows host service is unreachable | Probe the real listener's bind address through the selected VM route: `host-gateway` and either host alias can resolve without reaching Windows loopback. Renaming the alias alone is not a fix. Ask before changing listener binding, firewall or WSL networking |
| Mount is missing or becomes a directory | Check source existence, file/directory type and host-to-VM path translation before startup |
| Named volume appears empty | Check engine, project/volume identity and rootful/rootless connection; stores are separate, not automatically migrated |
| Buildx command or Dockerfile flag fails | Check the selected builder's real capabilities; Podman's compatibility alias is not full Buildx |
| Build succeeds but Compose pulls another image | Check local image name, target store, build output/export and pull policy |
| Dev Container opens but nested engine access fails | Verify the inside-container CLI and approved socket mapping independently of host launch |
| GPU profile parses but cannot start | Verify provider, host hardware/driver, machine toolkit/CDI and Compose device support; do not silently fall back to CPU |

For registry TLS problems, use the existing package-feed guidance only when its scope actually
applies. Credentials and private feed coordinates stay out of public guidance and diagnostics.

Rootful switching changes the visible Podman store. Do not use it as an automatic workaround for
bind permissions or missing data. Global relabeling, writable mounts, privileged mode and API-socket
exposure all require deliberate justification and approval.

VS Code documents selecting `podman` through `dev.containers.dockerPath`; alternate CLIs are not
officially supported. Change user settings only with approval and test Features, lifecycle scripts,
non-root ownership and socket access. Do not assume Docker-outside-of-Docker works unchanged.

Use bounded redacted logs and process exit codes. A health check may prove a service is listening
without proving credentials, migrations, protocol connectivity or the intended application adapter.

## Official References

* [Machine settings and storage separation](https://docs.podman.io/en/latest/markdown/podman-machine-set.1.html)
* [Docker-compatible API security](https://docs.podman.io/en/latest/markdown/podman-system-service.1.html)
* [Windows Docker API compatibility](https://podman-desktop.io/docs/migrating-from-docker/managing-docker-compatibility)
