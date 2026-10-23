# Read and Mutate in One Collection

Copy [the collection](../assets/collection.http) to the consuming repository's
`requests/widgets.http`, and [its dotenv example](../assets/collection.env.example) to
`requests/.env.example`. Keep a populated `requests/.env` ignored before adding local values.
This bundled skill asset is intentionally outside a consuming repository's `requests/` tree.

The two named requests are independent. The GET uses an explicit synthetic identifier; the POST
creates a resource. There is no response chaining that silently turns an approved read into a
mutation, and neither request is executed as part of this example's validation.

## Authentication and Approval

The asset deliberately contains **no authentication**, because it demonstrates request structure,
not an identity scheme. It is not directly usable against an `[Authorize]` API. Before use, add the
target's actual supported authentication using the existing request template and secret-handling
rules, and add every required variable exactly once to the colocated dotenv example. Never disable
server authorization to make the collection run.

Treat the synthetic URL as a placeholder, not a reachable service to probe. Replace it only in the
ignored local configuration with the explicitly approved destination. Read access can disclose
data; a GET still requires execution approval.

| Request | Approval must identify | Expected evidence |
| --- | --- | --- |
| `getWidget` | Method GET, intended environment, authentication source and resource scope | 200 with the permitted widget or 404; distinguish 401/403 from absence |
| `createWidget` | Method POST, environment, identity, payload and permitted resource creation | 201 with Location, or the API's documented 400/409 outcome |

The `# @note` marks a side effect; it is not an enforcement mechanism. Use **Send Request** for the
specific approved section, not a batch runner. After an uncertain POST timeout, determine whether
creation completed before retrying. Do not assume an idempotency key or cleanup endpoint exists.
Deleting the result is another mutation requiring approval; never automatically add a DELETE.

## Expected Errors Are Not Interchangeable

If the consuming API follows the [typed outcome example](../../dotnet-webapi/examples/typed-outcomes.md),
400 binding/validation errors and 409 business conflicts have different meanings. Verify its actual
schema and error contract rather than treating every non-201 response as the same failure.
This request asset does not prove the controller exists, and the controller example does not
grant permission to send these requests to a deployment.

## Static Validation

Require two uniquely named requests, matching dotenv keys, a mutation note before POST, and a
parseable synthetic JSON body. Verify ignored-file and editor-extension setup in the consumer.
Static fixture checks do not exercise REST Client interpolation, authentication, HTTP responses or
the selected environment; disclose those gaps until separately approved.
