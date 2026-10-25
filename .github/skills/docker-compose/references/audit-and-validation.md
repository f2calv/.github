# Compose Audit and Validation

## Review Matrix

Use the central instructions as the rule authority; this table describes the evidence to trace.

| Surface | Review evidence and common failure |
| --- | --- |
| Invocation/layout | Root stack and header match actual callers; automatic overrides or `COMPOSE_FILE` can change behavior |
| Profiles | Default infrastructure and optional builds/GPU/demo paths match intent; dependencies remain valid in each supported selection |
| Images | Supported major tags, variant/platform and publisher support verified; version-specific exceptions explained; no untagged/latest images or routine digest requirement |
| Build inputs | Context, Dockerfile and ignore rules contain the required sources; relative paths still work after consolidation |
| Readiness | Health command exists in the image and probes the required service; long syntax waits for healthy dependencies or successful initializer completion |
| Lifecycle | One-shot versus daemon restart policy matches purpose; dependency startup gating is not runtime recovery or migration correctness |
| Storage | Resolve every mount's host source, container target, mode and owner; state belongs in named volumes, tracked configuration is present/read-only |
| Isolation | Test writes/cleanup target disposable data or per-run databases/key namespaces; separate services only where mutation scope requires them; fixed global names can defeat project isolation |
| Networking | Standard/established host ports under the one-stack default; service DNS/container ports between containers; container localhost is itself |
| Exposure | Bind developer-only ports to loopback where practical; unnecessary public ports, privileged mode, host networking and Docker-socket access need explicit justification |
| Inputs/secrets | Fresh-clone prerequisites documented, real secrets ignored/external; `.env` interpolation differs from service `env_file` |
| Portability | Windows/Linux mounts, file permissions, line endings, host paths, GPU/device availability and image platforms match supported hosts |
| Documentation | Header owns endpoints/images/storage; README links to Compose instead of duplicating wiring; task/script commands, application configuration and cleanup match the model |

## Workspace and Consumer Checks

Record Dockerfile-to-Compose coverage under the central rule, including justified tool-only
exceptions. A missing stack is a coverage gap, not authorization to invent prerequisites or
containerize an otherwise infrastructure-free application.

Assume one stack at a time and keep standard/established ports. Build a cross-stack host-port matrix
only for an actual concurrent-run requirement; repeated standard ports across repositories are not
audit defects. Different Compose projects still compete for published ports if run together.
Independently trace test configuration and cleanup: a fixed endpoint may reach a development
dependency, and a dedicated container does not protect a client still targeting the old database or
key namespace. Do not add alternate ports or services instead of fixing client targeting.

For .NET tests, follow the shared
[test configuration rules](../../../instructions/dotnet.testing.instructions.md#integration-tests).
Use the existing configuration loader and preserve environment-variable overrides instead of
embedding connection-string fallbacks in C#. A service's Compose definition does not configure
the test process automatically.

Check Compose commands in wrapper scripts too. A valid model does not validate an obsolete
`docker-compose` executable dependency, invalid CLI arguments, wrong working directory or caller
that omits a required profile. Treat existing uncommitted Compose edits as the audited working-tree
state and preserve them during later synchronization.

## Mount and State Checks

Named volumes survive ordinary container recreation. Explicit external or globally named resources
can be shared across projects; a different `--project-name` alone does not isolate them.
Do not change database image majors or data-directory layout without a deliberate migration plan.
Health checks can report readiness without proving credentials, schema or application queries work.

Compare each stateful image's effective storage path with the mount target, including its
major-version-specific `VOLUME`/data-directory layout. A named volume at an obsolete path does not
protect the real data. When overriding `command`/`entrypoint`, check which publisher defaults are
lost, especially explicit storage-location flags. Preserve data already written to container layers
or anonymous volumes before recreation; do not simply change the mount and declare migration done.

Inspect bind-source existence and whether required non-secret configuration is tracked. Short bind
syntax can create a missing source as a directory at runtime; successful `config --quiet` is not
proof a file mount can start. For required configuration files, prefer long syntax with
`bind.create_host_path: false` when supported, so missing inputs fail rather than create misleading
directories. Do not read secret contents for this check.

Distinguish intentional disposable `tmpfs` test storage from persistent named volumes and anonymous
volumes inherited from an image. Report its actual stop/recreate loss behavior and memory budget;
do not migrate existing state or mandate persistence for a deliberately disposable fixture.

## Runtime Wiring From Source

Trace each demo's environment override to the exact consumed configuration key and provider
precedence. A syntactically valid but unused key can leave a container pointing at localhost or an
unrelated external dependency. Document IDE and container endpoints separately. Starting a local
database is not proof that the application selected its database adapter instead of in-memory state.
“Self-contained” demos must not silently inherit enabled cloud credential/bootstrap requirements.

Check a health probe's executable in the selected final image/stage, not in a Debug stage or build
toolchain. Startup dependencies should gate the selected provider and required model/seed
initializer, without introducing references to services in inactive profiles.

Review bootstrap commands as full process invocations. `docker compose run service command`
replaces the command but normally preserves the service entrypoint; appending `sh -c` to a
server entrypoint does not launch a shell. Use an intentional initializer or verified entrypoint
override, and check the chosen image actually contains the executable and required model tools.
Keep large models/GPU services optional and preserve existing downloaded data.

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
Do not infer runtime targeting from positional arguments to `config --services`: its output can
remain the active profile's service set. Verify the runtime command's selection semantics separately
without starting workloads unless authorized.
The wildcard activates all profiles; it does not replace individual checks and may select
combinations the application does not support.

YAML parsing/schema validation and active-model dependency validation are distinct. Inactive
profile content can still be parsed/validated; do not claim it is invisible to the parser.
Likewise, a successful configuration check proves neither image existence nor runtime readiness.

Use the application's documented variable sources. Synthetic overrides for isolated structural
checks must be reported as such, not as proof that a fresh clone works. Do not read real secret
files merely to silence missing-input validation. Missing required files are actionable blockers.
Check for automatically loaded `.env` files before invoking Compose, even with `--quiet`.
If real secret input is not authorized, report effective validation as blocked; an explicitly
approved synthetic environment can support a separate structural check, not secret-backed validation.
`--no-interpolate` / `--no-env-resolution`, where available, support partial inspection only; do
not label those checks complete effective-configuration validation.

Prefer `config --quiet` rather than printing the resolved model. `config`, `config --environment`
and diagnostic logs can expose secrets; do not persist or publish their full output.
Even validation errors may quote sensitive values, so redact before reporting.

Registry manifest inspection is separate network validation, not a local parser check.
For approved image checks use `docker buildx imagetools inspect <image>:<tag>` and verify required
platforms. Do not automatically pull images or enable digest resolution during a static audit.

## Runtime Validation Only With Authorization

Confirm Docker context, project identity, selected profile/services, standard ports or justified
overrides, expected side effects and cleanup before starting. Inspect existing resources read-only to avoid targeting
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
