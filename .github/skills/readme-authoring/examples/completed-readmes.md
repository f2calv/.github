# Completed README Examples

The conditional master outline is an authoring aid. These completed examples show which sections
survive once the product's actual contract is known; neither is a document to copy unchanged.

## Source-Only Library

Read the [completed library README](../../dotnet-performance/examples/utf8-count/src/Example.CountParsing/README.md)
beside its real project and implementation. It states the target framework, offers a project-reference
installation path rather than inventing a NuGet listing, and shows a complete console call with
its namespace and expected output.

The behavior section distinguishes parse failure from a valid zero, preserves the framework's
trailing-NUL behavior, and limits the allocation claim to the API boundary. There is no configuration
or DI section because the library exposes neither. No registry badges or license claims are invented.
The canonical README lives with the actual fixture; do not maintain a second copied version here.

## Local Reusable Workflow

Read the [completed workflow README](./reusable-workflow/README.md) beside its source template.
It includes a working same-repository caller, typed inputs with defaults, the complete output
forwarding path, and explicit permissions/secrets. It distinguishes the label it actually produces
from a report or artifact it does not produce.

There is no fictional release tag or Marketplace badge. The local workflow filename and copy step
are explicit, and an invalid supplied input does not silently fall back to the default.
The source contains no remote Actions, so no action-version claims need to be manufactured.

## Review the Evidence, Not Just Headings

| Claim | Evidence |
| --- | --- |
| Library accepts UTF-8 input and returns a count | Public method signature and implementation |
| Example prints `123` | Compile/run the shown console snippet against the fixture |
| No published package is advertised | Source-only installation and no speculative registry URL |
| Workflow defaults to summary | `workflow_call.inputs.mode.default` |
| Detailed mode returns `Detailed` | Extracted step execution and all three output links |
| No permissions or secrets are needed | No checkout, API calls, secret declarations or inherited secret consumption |
| Invalid mode fails | Exact allowlist and fixture assertions |

Keep these READMEs synchronized with their source and local validation. Do not turn a local shell
test into a claim that a GitHub workflow ran, or a microbenchmark into an application-wide speedup.
