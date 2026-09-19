---
name: rest-client-requests
description: 'Create, migrate, audit, and maintain VS Code REST Client .http and .rest files, including requests-folder layout, dotenv secrets, authentication, examples, references, and editor support.'
argument-hint: 'mode={add|update|migrate|audit} [scope=repository-or-workspace]'
user-invocable: true
compatibility: 'Requires VS Code with humao.rest-client to execute requests. Authoring and static validation are cross-platform.'
---

# REST Client Requests

## Overview

Maintain executable API examples for the Huachao Mao VS Code REST Client without leaking credentials
or scattering request files through source projects. Keep request collections discoverable under the
repository-root `requests/` directory and make each file safe to commit.

## Prerequisites

* Read the target repository's instructions and confidentiality rules before editing.
* Use `git mv` when relocating tracked request files so history remains visible.
* Install `humao.rest-client` in both `.vscode/extensions.json` and the Dev Container extension list
  when the repository has a Dev Container.
* Never execute a request without explicit approval. Requests can mutate remote systems.

## Quick Start

Use [the request template](assets/request.http) and
[the dotenv example template](assets/.env.example) when creating a collection.

```text
/rest-client-requests add requests/orders.http
/rest-client-requests migrate this repository
/rest-client-requests audit the workspace
```

| Mode | Contract |
| --- | --- |
| `add` | Create a request collection and its required variable documentation |
| `update` | Preserve behavior while changing requests, variables, or authentication |
| `migrate` | Move request files to the standard layout and update every reference |
| `audit` | Make no edits; report layout, secret, reference, and editor-support findings |

## Repository Layout

Use one flat request directory per repository:

```text
requests/
├── README.md
├── .env.example
├── service-admin.http
└── service-query.http
```

* Put every repository-owned `.http` and `.rest` file directly under root `requests/` unless a tool
  requires another location. Record and preserve any exception.
* Use lowercase kebab-case names that identify the API or workflow. Keep related requests together
  and separate unrelated APIs into different files.
* Do not create environment subdirectories. The REST Client resolves `{{$dotenv NAME}}` only from a
  `.env` file in the same directory as the request file.
* Keep reusable request bodies or fixtures under `requests/fixtures/`; reference them with paths
  relative to the request file.
* Add `requests/.env` to `.gitignore`. Track `requests/.env.example` and `requests/README.md`.

## Variables and Secrets

Classify every value before choosing where it lives:

| Value | Storage |
| --- | --- |
| Password, bearer token, API key, auth header, session value, private key | `requests/.env` or a prompt variable |
| Account, phone, device, tenant, subscription, or other private identifier | `requests/.env` |
| Environment-specific base URL or local file path | `requests/.env` |
| Stable public API endpoint | Literal file variable is acceptable |
| Pagination, test date, synthetic ID, model name, or harmless request option | Tracked file variable |

Endpoints are not credentials, but they can disclose private topology. In public repositories, use a
literal endpoint only when it is already public and appropriate to publish. Put private, local, and
environment-specific endpoints in `.env`.

Use uppercase namespaced dotenv keys. Prefer `<SERVICE>_BASE_URL`, `<SERVICE>_USERNAME`,
`<SERVICE>_PASSWORD`, `<SERVICE>_TOKEN`, `<SERVICE>_API_KEY`, and `<SERVICE>_<RESOURCE>_ID`.
Avoid generic names such as `HOST`, `USERNAME`, or `TOKEN` when several APIs share the directory.

```http
@baseUrl = {{$dotenv EXAMPLE_BASE_URL}}
@username = {{$dotenv EXAMPLE_USERNAME}}
@password = {{$dotenv EXAMPLE_PASSWORD}}
@token = {{$dotenv EXAMPLE_TOKEN}}
```

Use the extension's supported authentication forms without precomputing credentials:

```http
Authorization: Basic {{username}}:{{password}}
Authorization: Bearer {{token}}
X-Api-Key: {{$dotenv EXAMPLE_API_KEY}}
```

Use `# @prompt password` for a one-off secret that must not persist. The extension hides input only
for its recognized password names, so do not assume arbitrary prompt names are masked. Never ask the
user to send a secret through chat.

## Dotenv Files

Create a tracked `requests/.env.example` containing every referenced dotenv key exactly once. Values
must be synthetic and safe to publish:

```dotenv
EXAMPLE_BASE_URL=https://api.example.com
EXAMPLE_USERNAME=replace-me
EXAMPLE_PASSWORD=replace-me
EXAMPLE_TOKEN=replace-me
```

* Keep the example parseable as dotenv: one `NAME=value` assignment per line.
* Do not put real values, commented-out credentials, encoded credentials, or private identifiers in
  the example.
* Keep `requests/.env` untracked from the start. Verify with `git check-ignore -v requests/.env`.
* When migrating an existing ignored `.env`, move it without reading or printing its values. Update
  key names mechanically only when required, and tell the user which names changed.
* Do not commit `rest-client.environmentVariables` containing secrets to VS Code settings.
* Use `{{$processEnv NAME}}` only when the repository already standardizes process-level variables;
  otherwise prefer the colocated `.env` file.

## Request File Conventions

Start with a short title, optional documentation link, and file variables. Separate executable
requests with `###` and give important requests stable names with `# @name`.

```http
### Example API
### Public documentation: https://api.example.com/docs

@baseUrl = {{$dotenv EXAMPLE_BASE_URL}}
@token = {{$dotenv EXAMPLE_TOKEN}}
@resourceId = 00000000-0000-0000-0000-000000000000

### Get resource
# @name getResource
GET {{baseUrl}}/api/resources/{{resourceId}} HTTP/1.1
Authorization: Bearer {{token}}
Accept: application/json
```

* Use standard header casing such as `Content-Type`, `Accept`, and `Authorization`.
* Use `HTTP/1.1` consistently within a file when the existing collection includes protocol versions.
* Keep example payloads synthetic. Never embed real personal data, account identifiers, device
  addresses, phone numbers, or operational secrets.
* Mark intentionally failing examples in their section title, such as `Expected 400`.
* Add `# @note` before every `POST`, `PUT`, `PATCH`, or `DELETE` request. Omit it only when the
  operation is demonstrably read-only and the exception is explained beside the request.
* Use request variables for response chaining only within the same file.
* Do not treat `.http` files as automated tests unless CI executes and asserts them through a
  dedicated runner.

## Migration Workflow

1. Inventory tracked `.http` and `.rest` files, dotenv references, literal credentials, body-file
   paths, project includes, documentation links, scripts, and editor recommendations.
2. Check target paths for concurrent changes and filename collisions.
3. Create `requests/`, then move tracked files with `git mv`. Preserve one file per current API or
   workflow rather than combining unrelated collections during a location-only migration.
4. Move an existing ignored request `.env` to `requests/.env` without exposing its contents. Create
   `requests/.env.example` from variable names found in tracked files.
5. Normalize variable names and replace tracked private identifiers with dotenv references.
6. Update `.gitignore`, documentation links, script paths, comments, project metadata, and fixtures.
7. Reconcile `humao.rest-client` through the Dev Container skill when editor recommendations drift.
8. Run static validation before considering any live request.

## Validation

1. Confirm every tracked request file is under `requests/`, or document an explicit exception.
2. Confirm `requests/.env` is ignored and `requests/.env.example` is trackable.
3. Compare every `{{$dotenv NAME}}` reference with the keys in `.env.example`; fail on missing or
   unused keys.
4. Scan tracked request files and examples for literal authorization values, credential-shaped query
   parameters, private identifiers, and machine-specific absolute paths.
5. Verify request-body fixture paths resolve after moves.
6. Search the repository for references to old request paths.
7. Verify `humao.rest-client` is recommended for host and Dev Container use where applicable.
8. Run repository privacy scanning before committing public changes.
9. Ask before sending any request. State the method, endpoint class, authentication source, and
   expected side effects when requesting approval.

## Troubleshooting

| Symptom | Response |
| --- | --- |
| Dotenv variable is unresolved | Put `.env` in the same directory as the `.http` file and check the exact key casing |
| Request works before a move but not after | Update colocated dotenv and relative fixture paths |
| Secret appears in a tracked diff | Remove it, rotate it when real, and inspect history before publication |
| Endpoint should vary by environment | Move only the base URL to dotenv; keep public paths and payloads tracked |
| Host and Dev Container behave differently | Reconcile `humao.rest-client` in both extension surfaces |
| Request may mutate data | Add `# @note` and require explicit execution approval |

## References

* [REST Client extension](https://marketplace.visualstudio.com/items?itemName=humao.rest-client)
* [REST Client variables](https://github.com/Huachao/vscode-restclient#variables)
