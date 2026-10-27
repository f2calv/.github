# IDE Cache and Read-Only Test Probe

The [Compose template](../assets/compose.yaml.tmpl) is a synthetic local stack: an IDE-facing Redis
dependency and a one-shot read-only connectivity probe. It is not a complete
application, production topology or proof that integration tests passed.

## Adapting the Template

Copy/adapt its contents into the application's single root Compose file only when that dependency
is needed. If a stack already exists, integrate rather than overwrite it. The `.tmpl` suffix keeps
this reusable authoring asset distinct from a repository's operational root stack.

The image tag illustrates the supported-major policy. Verify its current publisher support and required
platforms before adoption; no digest or “latest verified release” claim is embedded.
There are no real credentials. This unauthenticated Redis example is limited to local development,
with loopback-only published ports; do not deploy it or expose it on a shared network.

## Intended Behavior

| Selection | Effective intent |
| --- | --- |
| Default | `cache` only, used by the application running in the IDE |
| Profile `test` | Unprofiled `cache`, plus one-shot `probe_test` |
| Explicit `up -d cache` | Only the IDE dependency |
| `run --rm probe_test` with test profile | One-off check of cache DNS/connectivity after readiness |

Activating the test profile does **not** turn off unprofiled development services. Use the
documented explicit service command when only a selected dependency is wanted.
The probe does not run the application's test suite, prove data isolation in the application
client, or exercise durable data recovery.

An IDE connects to `localhost` on the standard Redis port. A container connects to
`cache:6379`. Do not put `localhost:6379` in a container's Redis configuration and expect it
to reach the other service. Endpoint details live in the template header, not a copied README table.

## Standard Ports and Test Data

This example assumes one stack runs at a time and publishes the standard Redis port, with one
project-scoped named volume. Do not add a second Redis service or invented port merely because
tests exist. A distinct project name separates generated resources, not host ports. Only introduce
port overrides when simultaneous operation is a real, approved requirement.

The probe only sends `PING`; it writes no test data. Application tests using this cache must configure
the correct endpoint and use unique per-run keys with cleanup restricted to those keys. If tests
must flush a database or cannot otherwise bound their mutations, use a dedicated disposable target
instead; key prefixes cannot make `FLUSHDB` safe. Merely defining a profile does not redirect tests.
Never flush the IDE cache to prepare tests. This template requires no cleanup that deletes data;
ordinary Compose teardown retains named volumes. Any later data deletion needs separate approval.

For a tracked Redis configuration file, add an explicit read-only mount and its `.gitignore`
allow-list entry together. For real secrets, use the repository's ignored external input mechanism;
do not add credentials to this template or commit a `.env`.

## Acceptance Cases

| Case | Required evidence |
| --- | --- |
| Default configuration | Service set is exactly `cache`; no source-built app starts |
| All-profile configuration | Both services and the single declared volume form a valid model |
| Test profile | Cache is healthy before the probe runs |
| Probe success | Exit code 0 and expected `PONG`; no application-test claim |
| Cache unhealthy | Dependent probe does not falsely report success |
| Port already used | Explicit diagnosed startup failure, not a silent port change |
| Another repository uses port 6379 | Not a defect under sequential operation; concurrent use needs explicit planning |
| Different Compose project | Generated volumes differ; the published host port remains unchanged |
| Application test writes a key | Only its unique namespace is written/cleaned; development keys remain untouched |
| Test requires database-wide reset | Dedicated disposable target selected before execution; no IDE-cache flush |
| Ordinary teardown/recreation | Development data is retained under its original project identity |

Configuration checks require no container startup. Runtime and application-test cases require
separate authorization and isolated resources; report which were actually executed.
