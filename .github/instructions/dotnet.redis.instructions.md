---
description: 'Redis key-naming, consumer-group, TTL and key-migration conventions for feature-scoped keys.'
applyTo: '**/*Redis*.cs,**/*Redlock*.cs,**/*.lua,**/appsettings*.json'
---

# Redis Key Naming

When a project uses a feature enum (e.g. `AppFeature`) to gate services, derive the domain segment of every Redis key from the **lowercase enum member name** so that key prefixes stay tightly coupled to the feature taxonomy (e.g. `AppFeature.Billing` → `billing:`, `AppFeature.Notifications` → `notifications:`).

- **All lowercase**, colon-separated segments: `{domain}:{type}:{detail}`.
- **Domain** — derived from the feature enum member name via `nameof(AppFeature.Member).ToLowerInvariant()`. Cross-feature keys use a functional domain (e.g. `comms`, `lock`, `stats`).
- **Standard type segments**:

| Segment | Redis Type | Purpose |
| --- | --- | --- |
| `snapshot` | Hash | Current state (field per entity) |
| `series` | Sorted Set | Time-series readings (score = UTC ticks) |
| `stream` | Stream | Event/message streams |
| `cache` | String | Temporary data with TTL |
| `lock` | String | Distributed locks (Redlock) |
| `stats` | Hash | Observability / call counters with TTL |

- **Detail** — further qualifiers such as entity IDs, date partitions (`{yyMMdd}`, `{yyyy-MM-dd}`), or sub-categories (e.g. `values`, `timestamps`).
- **Consumer groups** — use `{domain}:{role}` format (e.g. `billing:processors`, `comms:agents`).
- **Stats keys** — date-partitioned with a 7-day TTL: `stats:{domain}:{yyyy-MM-dd}`. Hash fields are the method or operation names.
- **Lock keys** — `lock:{domain}:{resource}` format string, configured via `RedisKeyFormat` in `appsettings.json`.
- **Config-driven keys**: Snapshot and series key names should be stored in `appsettings.json` per-sink settings (via a settings dictionary), not hardcoded in service code. This allows key migration by config change alone.
- **Key sync on rename**: When renaming Redis keys, update `appsettings*.json`, Lua scripts, and any C# code that constructs or references the old key name in the same commit. Existing Redis data under the old key will be orphaned — treat key renames as a fresh-start migration.
