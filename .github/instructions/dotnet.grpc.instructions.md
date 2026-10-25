---
description: '.NET gRPC contract and transport invariants; use the dotnet-grpc skill for implementation, diagnosis, Kubernetes reliability and workspace reviews.'
applyTo: '**/*.proto,**/*Grpc*.cs,**/*Grpc*/**/*.cs'
---

# .NET gRPC

Use the [gRPC skill](../skills/dotnet-grpc/SKILL.md) before changing contracts, clients, servers or
gRPC deployment behavior. It owns the workflow, references, patterns and acceptance cases.

- Preserve published protobuf field numbers, wire types and service/method identities; reserve
  removed fields and choose explicit versioning for incompatible changes.
- A plaintext gRPC listener must be HTTP/2-only. Shared HTTP/1.1 and HTTP/2 listeners require TLS
  negotiation; validate the protocol through every intermediary.
- Keep cancellation/deadline, transport keepalive, application progress/acknowledgement and durable
  replay as separate contracts. Do not claim any one substitutes for another.
- Retry mutations only with an explicit replay-safety contract. Expose uncertain outcomes rather
  than hiding them behind empty/default results.
- Do not log payloads, credentials or user identifiers in gRPC metadata, traces or metric labels.
