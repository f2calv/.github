# Ownership Contract

Inventory the election surface and define the ownership contract before changing implementation.

1. Find every `IDistributedLockFactory`, `IRedLock`, `CreateLockAsync`, `RedlockConfig`,
   `RedlockProfiles`, leadership state and leader-gated worker. Include registration, configuration,
   tests, local orchestration, deployment values, health checks, metrics and operational docs.
2. Classify the protected work:
   - One singleton worker, such as a scheduler, notifier or external connection monitor.
   - A set of related loops that must share one ownership lifetime.
   - Independently owned partitions, such as a tenant/account/workload combination.
   - Short critical sections or cache-miss suppression, which are not long-lived leadership.
3. Define exactly which side effects require ownership and which activities must run on every
   replica. Do not put HTTP serving, health endpoints or unrelated background work behind a global
   lease accidentally.
4. Define the resource identity, timing profile, contention policy, startup completion, lease-loss
   response, shutdown behavior and intended failover bound before changing implementation.
5. Search for reusable lifecycle/state helpers before adding another election loop. Separate
   generic acquisition, cancellation and state mechanics from business callbacks and partition
   identity. Use the shared caching library for reusable .NET mechanics; use a shared chart or
   workflow only for the deployment or automation contract it actually owns. Do not imply that an
   application-specific runtime helper already exists in the caching package.
