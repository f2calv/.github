# State, Health and External Connections

Expose coherent election state and readiness, and bind leader-owned connections and callbacks to ownership.

## State and Health

- Keep a thread-safe, coherent snapshot of election phase, ownership-run identity, acquisition
  state, worker startup/progress and stop/failure state. Distinguish contending, starting, active,
  recovering, faulted and stopping where those phases exist.
- Treat election state and business readiness separately: a held lease does not prove that the
  external connection, warm-up or protected worker is ready.
- For a coordinated pipeline, include engine-running state and required-reader startup/liveness
  in the readiness projection. A startup latch is not a permanent readiness guarantee. On stop,
  cancel and await producers/readers before closing channels they still write to, and complete
  the rest of the pipeline's cleanup within the ownership lifetime.
- Distinguish local heartbeat/progress time from authoritative lease-renewal evidence. Do not name
  a timestamp "last renewed" if it only records an application's periodic observation.
- Observe acquisition latency, contention, ownership transitions, lease loss, worker failures and
  recovery. Keep labels bounded and free of resource/account identifiers and private content.
- Define active-worker readiness separately from process liveness and HTTP readiness. A healthy
  standby is not a failed process; do not make all followers unready for ordinary HTTP traffic or
  trigger restart storms merely because they do not own the lease.
- Ensure metrics, health endpoints, diagnostics and any leader-only command gateways use the same
  authoritative state rather than independent booleans that can disagree.

## External Connections and Callbacks

- Include every user of a leader-owned connection in the ownership lifetime, including outbound
  queue readers and command writers registered as separate background features. Cancel and join
  those users before disposing the connection; standbys must not consume commands they cannot send.
- For separately registered commands or reconciliation, serialize operation admission with ownership
  withdrawal, link the caller and ownership tokens, and await admitted users before logout. Keep an
  auxiliary-user cancellation lifetime separate from a dispatcher that must drain on a still-owned
  normal/fault exit; lease loss must cancel both. Ownership-only cancellation need not terminate an
  otherwise healthy periodic feature or masquerade as request cancellation.
- Fail closed before ownership state is initialized and throughout startup. A default "election
  inactive" flag is not permission for live commands. Restrict replay bypass to the actual isolated
  execution adapter, without granting live auxiliary-operation admission. Reject unsupported mixed
  live/replay configurations before registering transports or starting side effects.
- Capture the authoritative partition identity atomically with operation admission. Resolve owned
  connections from that identity, not an unrelated worker's default connection or request parameters;
  host registration, execution and auxiliary workers must agree on runtime selection.
- Classify recovery after cleanup and lease disposal. Retry only the intended business failure, not
  an acquisition/release/teardown error with a similar exception type. Preserve a previously observed
  child failure's identity when joining it again; do not relabel it as a new teardown failure. Reuse
  business-fault classification across consumers without merging their recovery budgets. Known
  permanent causal failures must override transport-shaped wrappers; retry an aggregate only when
  every constituent fault is recoverable, and propagate unknown failures rather than assuming recovery.
- Treat explicit external authentication rejection separately from transient transport failure. Check
  exception paths as well as false login results; an exception must not bypass the intended backoff
  or cause credential submission on every re-election. Transient cached-session validation must not
  silently fall back to password login. Preserve the authentication cause alongside teardown failures.
- Treat explicit provider quota rejection as backpressure, not evidence of an expired session.
  Coordinate admission and cooldown across concurrent owned callers, and dispatch only after a
  limiter grants admission. Retry explicit rejections on the same session with a bounded,
  cancellation-aware budget and respect longer provider retry delays; never replay an ambiguous
  write as quota recovery. Quota during cached-session validation must not trigger password-login
  fallback. Re-election and process restart do not replenish an external allowance.
- Decide terminal external-service recovery with the operator, including authentication rejection
  and exhausted quota recovery. When restart itself would repeat rejected credentials or requests,
  stop owned work, finish cleanup/release, withdraw command admission and readiness, and
  park until explicit restart rather than failing liveness/startup into a restart storm. Keep probe
  registration names scoped and test the stopped state after the supervisor transition, not merely
  lease release. Document whether the stop is client/process-local or durable across replicas and
  rollouts; a local latch is not an account-wide circuit breaker.
- Emit sanitized terminal-stop notifications through the application's existing operator channel,
  after owned cleanup/release and with the host token rather than a cancelled ownership token.
  Notify once per stopped process/run, not on every contention or recoverable retry. Do not include
  credentials, response bodies, account/resource identifiers or arbitrary exception messages.
  Expected notification-transport failures must be explicit without undoing operator-stop containment.
  Distinguish queue acceptance from actual delivery, including existing throttling/stale-event rules.
- Verify an independent sustained-Unready alert for parked workers: inspect the deployed readiness
  expression (including Running-but-not-Ready pods), rule selector, active receiver route and adapter
  health. Healthy liveness does not imply readiness or suppress readiness alerts. Record the actual
  hold/repeat timing and that zero replicas cannot generate pod-readiness alerts. Do not claim
  end-to-end paging without an authorized delivery check.
- Create fresh callback/reconnection buffers for each ownership run. Detach handlers and await
  asynchronous connection disposal on every exit, including partial startup. Fence late callbacks
  by their run and connection identity, not a mutable reference to the latest run.
- Replace untracked asynchronous event handlers with synchronous admission into an owned buffer and
  an awaited publisher. Propagate publisher/decoding failures through supervision, pass the run token
  to publication, and document buffering and non-replay semantics. SDK callbacks that cannot apply
  backpressure need an explicit overflow policy before a bounded buffer can safely replace them.
- Withdraw readiness on cancellation before waiting for cleanup. Serialize that transition with
  callback/health updates so a late update cannot reactivate an old run. An empty connection set
  does not establish readiness.
- Distinguish request-only disconnect APIs from awaited teardown. Retain producer and watchdog
  tasks and join them before reusing a connection or draining persistent buffers; starting a new
  subscription must not reactivate an old loop through a shared mutable subscribed flag.
- Keep reusable transport ownership separate from a lease session. Logout stops owned streams;
  final service disposal releases shared HTTP clients. Test resubscription with an uncancelled
  host token as well as shutdown, because host cancellation can conceal missing per-session stops.
- Validate streaming HTTP status and declared media type before JSON decoding. Test rejected
  HTTP/HTML responses through an injected transport alongside normal stream records, and report
  safe status/type diagnostics without response bodies or account identifiers. A leading '<' in
  historical parser errors suggests a non-JSON response but does not establish its HTTP status.
