# Implementation Plan: Spec Kit Extension Pilot

**Branch**: `f2calv/2026-10-updates4` | **Date**: 2026-10-28 | **Spec**: [Specification](./spec.md)

**Status**: Bounded local pilot verified, including owner-confirmed native editor invocation and resource loading.

## Summary

Adapt one trusted required-only archive into a real Spec Kit 1.2.3 extension. Preserve native bytes
under `resources/library/`, add a thin read-only loading command and generate a one-entry catalog.
Use the real existing catalog/installer rather than implementing a second resolver or installer.
Keep the original `skill-archive/1` format unchanged; this adapter produces a distinct pilot artifact.

## Technical Context

- PowerShell 7.4+ on Linux; observed 7.6.9. Use built-in .NET ZIP, JSON and SHA-256 APIs.
- Reuse installed Spec Kit 1.2.3 and Pester 5.7.1, the existing archive builder and output-path helper.
- No packages, new framework, production service or separate project.
- Source ZIP and total payload are limited to 64 MiB; source members to 16 MiB. This is a bounded
  local pilot, not a throughput or cross-runtime reproducibility claim.
- Require a new absolute output directory under an existing unlinked trusted parent outside source.
  Exclusive creation refuses existing output; failures after reservation retain partial output.
- Use approved isolated consumers and loopback-only hosting. Keep generated files and consumer
  installation state out of canonical sources and tracked distribution configuration.
- Validate focused tests through `npm run test:ps`, real CLI operations and actual editor invocation
  as separate gates. The editor gate is not closed by file existence or manual reads.

## Constitution Check

| Principle | Design and post-design result |
| --- | --- |
| I: Canonical ownership | Pass: copy committed bytes only; wrappers and catalog are generated. |
| II: Progressive loading | Pass: owner confirmed native command invocation and on-demand installed-only resource reads. |
| III: Evidence | Pass: pinned runtime contracts and real CLI checks verified; owner-reported editor results remain distinct from manual reads. |
| IV: Metadata separation | Pass: consume existing required-only evidence; no new dependency schema, authored versions or consumer-state authority. |
| V: Approvals | Pass: explicit focused-test/build/loopback/consumer-sandbox approvals; no publication or standing commit permission. |

No principle exception is needed. Implementation evidence is not acceptance of the broader distribution ADR.

## Project Structure

### Documentation

Use this feature's [research](./research.md), [data model](./data-model.md),
[contract](./contracts/extension-pilot.md), [validation guide](./quickstart.md) and [tasks](./tasks.md).

### Source Code

```text
.github/skills/skill-library/
  SKILL.md
  scripts/Invoke-Extension.ps1
  scripts/Invoke-Tests.ps1
  scripts/tests/Invoke-Extension.Tests.ps1
```

Reuse the required-only archive as the adapter boundary, existing output-path checks and adjacent
Pester conventions. Generate artifacts and consumer fixtures outside this checkout.

## Complexity Tracking

No exception or new infrastructure. General installation, optional downloads, upgrades, recovery
redesign, publishing and deterministic extension-format guarantees are outside this pilot.
