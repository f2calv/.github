# IDE Cache and Isolated Test Cache

The [Compose template](../assets/compose.yaml.tmpl) is a synthetic local stack: an IDE-facing Redis
dependency, an independent test cache and a one-shot connectivity probe. It is not a complete
application, production topology or proof that integration tests passed.

## Adapting the Template

Copy/adapt its contents into the application's single root Compose file only when that dependency
is needed. If a stack already exists, integrate rather than overwrite it. The `.tmpl` suffix keeps
this reusable authoring asset distinct from a repository's operational root stack.

The image tag illustrates major/minor pinning. Verify its current publisher support and required
platforms before adoption; no digest or “latest verified release” claim is embedded.
There are no real credentials. This unauthenticated Redis example is limited to local development,
with loopback-only published ports; do not deploy it or expose it on a shared network.

## Intended Behavior

| Selection | Effective intent |
| --- | --- |
| Default | `cache` only, used by the application running in the IDE |
| Profile `test` | Unprofiled `cache`, plus `cache_test` and one-shot `probe_test` |
| Explicit `up -d cache_test` with test profile | Only requested test infrastructure and its dependencies |
| `run --rm probe_test` with test profile | One-off check of test-cache DNS/connectivity after readiness |

Activating the test profile does **not** turn off unprofiled development services. Use the
documented explicit service command if only test infrastructure is wanted.
The probe does not run the application's test suite, prove data isolation in the application
client, or exercise durable data recovery.

An IDE connects to `localhost` and the configured published port. A container connects to
`cache` or `cache_test` on container port 6379. Do not put `localhost:16380` in a container's
Redis configuration and expect it to reach the other service.

## Data and Port Isolation

Development and test services have separate project-scoped named volumes and host ports.
Before authorized simultaneous runs, choose unused `CACHE_PORT` and `CACHE_TEST_PORT` values.
A distinct project name also separates generated resources, but does not change the host ports.
Avoid adding global volume names or fixed container names that undo isolation.

The application test configuration must target `cache_test`/its host endpoint with per-run key
namespaces as appropriate. Merely defining a test service does not redirect the application's tests.
Never flush the IDE cache to prepare tests. This template requires no cleanup that deletes data;
ordinary Compose teardown retains named volumes. Any later data deletion needs separate approval.

For a tracked Redis configuration file, add an explicit read-only mount and its `.gitignore`
allow-list entry together. For real secrets, use the repository's ignored external input mechanism;
do not add credentials to this template or commit a `.env`.

## Acceptance Cases

| Case | Required evidence |
| --- | --- |
| Default configuration | Service set is exactly `cache`; no source-built app starts |
| All-profile configuration | All three services and both declared volumes form a valid model |
| Test profile | Test dependency is healthy before the probe runs |
| Probe success | Exit code 0 and expected `PONG`; no application-test claim |
| Test cache unhealthy | Dependent probe does not falsely report success |
| Port already used | Explicit diagnosed startup failure, not a silent port change |
| Different Compose project | Generated volumes differ; occupied host ports still need overrides |
| Application test writes a key | Key appears only in the intended test cache/namespace |
| Ordinary teardown/recreation | Development data is retained under its original project identity |

Configuration checks require no container startup. Runtime and application-test cases require
separate authorization and isolated resources; report which were actually executed.
