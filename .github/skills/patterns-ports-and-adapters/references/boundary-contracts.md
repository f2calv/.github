# Boundary Ownership and Semantic Contracts

## What the Port Belongs To

The application owns the capability it needs. The adapter references that contract and translates
to its provider. The composition root references both to wire them. A contract may live beside its
application service or in an existing deliberate contracts assembly; do not create an assembly
merely to move one interface.

An inbound adapter invokes an application use case; it should not contain the business decision.
An outbound adapter implements a needed external capability; it should not decide unrelated
application policy. Some validation is provider-specific, but domain rules must not disappear when
the provider is replaced by a fake or another implementation.

Use the [modular monolith boundary example](../../patterns-modular-monolith/examples/layered-module-boundaries.md)
for project-reference checks. Here also inspect:

- SDK/EF types or `IQueryable` leaking through return values, callbacks or exceptions.
- Provider status strings reused as business state.
- `IServiceProvider` or reflection moving selection back into application code.
- Generic CRUD ports that hide transaction/concurrency semantics the use case actually requires.

## Design for Real Semantics

| Concern | Contract question |
| --- | --- |
| Authority | Who owns the source of truth, and can the result be stale? |
| Validation/authorization | What trusted caller context is required, and who checks it? |
| Absence | Is not-found an expected typed result, distinct from dependency failure? |
| Mutation | What is the commit point, idempotency scope and ambiguous-outcome behavior? |
| Concurrency | Is there a revision/precondition, and what constitutes conflict? |
| Cancellation | Can cancellation stop work or only stop waiting? Could an effect already exist? |
| Resources | Who owns returned streams/leases and when must they be released? |
| Limits | What bounds payload, paging, duration and parallel operations? |

Map recognized provider outcomes only. Do not catch every exception and return null/false.
Keep unexpected failures diagnosable through the application's exception policy without exposing
raw provider content or credentials. An anti-corruption mapping translates concepts, not merely
renames JSON properties; preserve distinctions such as pending versus completed or conflict versus
unavailable.

## Substitution Without Fiction

Two implementations satisfy the same port only if their observable required behavior agrees.
An in-memory fake with immediate visibility cannot establish an eventually consistent provider's
read-after-write guarantee. A file adapter cannot claim a remote store's transaction semantics
without implementing them.

Use capability-specific contracts when only some providers support an operation and real consumers
need it. Alternatively reject unsupported selection/operations explicitly at the boundary. Do not
return empty output or pretend work completed because a provider lacks the feature.

Composition-time provider selection belongs to DI. Per-request selection still needs an explicit
trusted selection contract, isolated lifetime and authorization; never let an untrusted string
select arbitrary endpoints, types or credentials.

## Shared Behavioral Tests

Keep common expectations in the existing test framework, not copied per provider. Parameterize
fixtures only when setup/lifecycle differences justify it. Test-specific fake shortcuts must be
documented rather than silently relaxing the production contract.

Separate shared required behavior from provider-specific conformance (serialization, SQL, locking,
upstream quotas). Use isolated provider-backed tests where needed. Verify the application can
execute its policy using a controlled fake without initializing the real SDK.
An interface with a mock is evidence of a seam, not proof that every architecture boundary is sound.
