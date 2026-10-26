---
description: 'Docker Compose conventions for local development environments — file layout, volume taxonomy, image tags, standard ports, readiness, profiles and secrets.'
applyTo: '**/docker-compose*.yml,**/docker-compose*.yaml,**/compose*.yml,**/compose*.yaml'
---

# Docker Compose

Use the `docker-compose` skill for creation, workspace audits, troubleshooting and validation
procedures; this file remains the authority for Compose conventions.

Compose describes the **local development and demo environment**; it is never the deployment
target. Optimise it for "clone and run", not for production fidelity.

## File Layout

- A repository with an application/service Dockerfile should also have a useful local Compose
  environment. Tool-only images, tooling-runner Dockerfiles and Dockerfiles used only to build
  Dev Containers are exempt; do not add an empty stack merely to satisfy coverage. A Dev Container
  Dockerfile does not exempt a separate application/service Dockerfile in the same repository.
  Libraries may still need Compose for integration dependencies.
- One Compose file per repository, in the root. Use profiles instead of
  `docker-compose.override.yml` or per-environment files.
- Never include the obsolete top-level `version:` key.
- Open the file with a header comment listing what the default `docker compose up` starts, each
  profile with its command, and the published endpoints. Keep it accurate; it is the first thing a
  contributor reads.
- Delete commented-out services, volumes and settings; git keeps history.

## Volume Taxonomy

Getting mounts wrong silently pollutes the working tree with runtime state.

- **Tracked configuration** lives in a dedicated tracked directory, bind-mounted read-only:
  `./.docker/service.conf:/etc/service/service.conf:ro`.
- **Volatile or regenerable data** — databases, caches, emulator state, downloads — uses a named
  volume, never a bind mount: `database_data:/var/lib/database`.
- Local Compose runtime data, including existing writable Docker bind mounts, is disposable by
  default. Correct the storage definition without building a migration or preserving that state;
  only an explicit repository requirement makes local state non-disposable. This does not extend
  to tracked configuration, host fixtures, credentials/account registrations or production data,
  and does not itself authorize running destructive cleanup commands.
- **Host fixtures** the application only reads come from a gitignored directory, mounted `:ro`.
- Every bind mount is `:ro`. A writable bind mount needs a comment beside it giving the reason.
- Scope variable defaults to a subdirectory; `${SOME_DIR:-.}` mounts the whole repository.
- Name volumes in `snake_case`, prefixed with the owning service; never a bare `data`.

The tracked configuration directory is allow-listed in `.gitignore` with the same deny-then-allow
form as `.dockerignore`:

```gitignore
.docker/*
!.docker/service.conf
```

- Add the `!` entry in the same change as the mount that consumes the file.
- Never widen the deny rule to hide files a service writes; move that path to a named volume.

## Images

- Prefer supported major-version tags for local development and test images, retaining a required
  variant suffix, for example `redis:8` or `postgres:18-alpine`. Do not require minor/patch pins or
  immutable digests merely for reproducibility in these disposable environments. Dockerfile
  base-image and production-release pinning remain separate policies.
- An untagged image means `latest` and is a defect. If upstream publishes no usable major alias,
  retain a verified version-specific tag and explain the exception beside it. Use a digest only
  when no usable versioned tag exists or a specific requirement justifies it; document the reason.
- Before selecting a tag, confirm it exists and publishes the platforms you need with
  `docker buildx imagetools inspect <image>:<tag>`; the newest tag in a registry listing can be a
  nightly or single-architecture build.
- Check compatibility with the deployed dependency where relevant, but do not force local major
  tags and production chart pins to use identical tag precision.

## Ports and Test Data

- Assume one local Compose stack runs at a time. Use services' standard or established host ports,
  such as Redis `6379` and PostgreSQL `5432`; do not invent per-repository/test ports or extra
  configuration solely to support hypothetical concurrent stacks. Bind developer-only ports to
  loopback where practical.
- Add port overrides or separate published endpoints only for a demonstrated requirement, with
  user agreement. Diagnose an occupied port explicitly rather than silently changing it.
- Port coexistence is not data isolation. Use per-run databases or key namespaces and disposable
  test targets as appropriate. Separate services/volumes are warranted when destructive operations
  cannot be scoped safely, not merely because a test profile exists. Never reset development data.

## Readiness and Restarts

- Give a service a `healthcheck` when another service depends on it, or when a developer would
  otherwise watch logs to see whether it is ready.
- Depend on state, not start order: `condition: service_healthy` for long-lived dependencies and
  `condition: service_completed_successfully` for one-shot initialisers. A bare `depends_on` list
  only orders container start.
- One-shot initialisers use `restart: "no"`; long-lived services use `restart: unless-stopped`.

## Profiles

- The default `docker compose up` starts infrastructure only; the application under development runs
  from the IDE against it.
- Anything that builds from source, needs a GPU, pulls a large model or exists only for a demo goes
  behind a profile named for what it delivers (`demo`, `harness`), documented in the header.
- Prefer an existing Compose file's test profile for reusable local integration-test services rather
  than launching ad hoc containers. Apply the data-safety rules above; tests must never reset a
  shared database or flush a development Redis instance. Document startup and cleanup explicitly.

## Secrets

- Inline only well-known public development constants, such as an emulator's published key or a
  local database password.
- Real values come from a gitignored mount or `env_file` with a safe default so a fresh clone still
  starts: `${USER_SECRETS_DIR:-./.secrets}:/path/in/container:ro`.
- Never commit a `.env`; gitignore it alongside the secrets directory.

## Validation

- Validate all profiles after an edit with `docker compose --profile '*' config --quiet`, and check
  default and individually supported profile selections separately. Inactive services can still
  be parsed; all-profile validation alone does not prove each selection's dependency graph works.
- When a repository keeps a second Compose file for a variant topology, such as a replication
  cluster, fold it into the main file behind a profile, and update every script, solution file and
  README that referenced the old file in the same change.
