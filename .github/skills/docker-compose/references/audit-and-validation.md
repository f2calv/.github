# Compose Audit and Validation

## Review Matrix

Use the central instructions as the rule authority; this table describes the evidence to trace.

| Surface | Review evidence and common failure |
| --- | --- |
| Invocation/layout | Root stack and header match actual callers; automatic overrides or `COMPOSE_FILE` can change behavior |
| Profiles | Default infrastructure and optional builds/GPU/demo paths match intent; dependencies remain valid in each supported selection |
| Images | Version/platform and publisher support verified; no untagged/latest images; compare related chart versions only where actually applicable |
| Build inputs | Context, Dockerfile and ignore rules contain the required sources; relative paths still work after consolidation |
| Readiness | Health command exists in the image and probes the required service; long syntax waits for healthy dependencies or successful initializer completion |
| Lifecycle | One-shot versus daemon restart policy matches purpose; dependency startup gating is not runtime recovery or migration correctness |
| Storage | Resolve every mount's host source, container target, mode and owner; state belongs in named volumes, tracked configuration is present/read-only |
| Isolation | Development/test stacks use distinct data, ports and namespaces; fixed `name`, external volumes or `container_name` can defeat project isolation |
| Networking | Container-to-container traffic uses service DNS/container ports, IDE traffic uses published host ports; container localhost is itself |
| Exposure | Bind developer-only ports to loopback where practical; unnecessary public ports, privileged mode, host networking and Docker-socket access need explicit justification |
| Inputs/secrets | Fresh-clone prerequisites documented, real secrets ignored/external; `.env` interpolation differs from service `env_file` |
| Portability | Windows/Linux mounts, file permissions, line endings, host paths, GPU/device availability and image platforms match supported hosts |
| Documentation | Header, README, task/script commands, configuration endpoints and cleanup agree with the effective model |

Named volumes survive ordinary container recreation. Explicit external or globally named resources
can be shared across projects; a different `--project-name` alone does not isolate them.
Do not change database image majors or data-directory layout without a deliberate migration plan.
Health checks can report readiness without proving credentials, schema or application queries work.

## Configuration Validation Without Running Containers

Check `docker compose version` and relevant `--help` locally before relying on version-specific
flags. Supply absolute file/project-directory paths; do not rely on shell working-directory state.
Example commands use synthetic paths and must be adapted to the actual invocation:

```powershell
docker compose --project-directory 'C:\work\example' -f 'C:\work\example\compose.yaml' config --quiet
docker compose --project-directory 'C:\work\example' -f 'C:\work\example\compose.yaml' --profile '*' config --quiet
docker compose --project-directory 'C:\work\example' -f 'C:\work\example\compose.yaml' --profile test config --quiet
docker compose --project-directory 'C:\work\example' -f 'C:\work\example\compose.yaml' config --services
```

Repeat with each documented profile and required combination. Check the service list against
expected selections, including direct-service invocation semantics: targeting one profiled service
does not automatically start every peer that shares its profile.
The wildcard activates all profiles; it does not replace individual checks and may select
combinations the application does not support.

YAML parsing/schema validation and active-model dependency validation are distinct. Inactive
profile content can still be parsed/validated; do not claim it is invisible to the parser.
Likewise, a successful configuration check proves neither image existence nor runtime readiness.

Use the application's documented variable sources. Synthetic overrides for isolated structural
checks must be reported as such, not as proof that a fresh clone works. Do not read real secret
files merely to silence missing-input validation. Missing required files are actionable blockers.
`--no-interpolate` / `--no-env-resolution`, where available, support partial inspection only; do
not label those checks complete effective-configuration validation.

Prefer `config --quiet` rather than printing the resolved model. `config`, `config --environment`
and diagnostic logs can expose secrets; do not persist or publish their full output.
Even validation errors may quote sensitive values, so redact before reporting.

Registry manifest inspection is separate network validation, not a local parser check.
For approved image checks use `docker buildx imagetools inspect <image>:<tag>` and verify required
platforms. Do not automatically pull images or enable digest resolution during a static audit.

## Runtime Validation Only With Authorization

Confirm Docker context, isolated project name, selected profile/services, port overrides, expected
side effects and cleanup before starting. Inspect existing resources read-only to avoid targeting
someone else's stack. A project name does not fix globally named resources or host-port collisions.

Use bounded readiness waits supported by the installed Compose CLI. For one-shot services, assert
their actual exit status; `up --wait` alone does not prove the job's intended side effects.
For applications, verify protocol connectivity from the intended caller (IDE versus container),
not just container state. Database health is not proof a migration or seed ran.

On failure, inspect service state, bounded redacted health output and the relevant network/mount.
Do not restart/recreate unrelated services, publish environment dumps or delete volumes to
“fix” permissions. Stop/remove only resources created for the approved check and retain data
unless deletion was explicitly approved.

## Official References

- [Compose config](https://docs.docker.com/reference/cli/docker/compose/config/)
- [Profiles and explicit targeting](https://docs.docker.com/compose/how-tos/profiles/)
- [Startup and dependency conditions](https://docs.docker.com/compose/how-tos/startup-order/)
- [Variable interpolation](https://docs.docker.com/compose/how-tos/environment-variables/variable-interpolation/)
- [Compose networking](https://docs.docker.com/compose/how-tos/networking/)
- [Volumes](https://docs.docker.com/reference/compose-file/volumes/)

Consult the relevant current reference when a review depends on CLI or model semantics.
