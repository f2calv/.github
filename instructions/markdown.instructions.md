---
description: 'README consistency, structure, Mermaid diagram and Markdown linting conventions for documentation.'
applyTo: '**/*.md'
---

# Documentation

Where these rules refer to a *project*, read it as the repository's primary unit of delivery — a project, library, module, chart, reusable workflow, action or deployment layer, whichever that repository publishes.

## README Consistency

- **Every project has a `README.md`**: when adding a new project, module, package, chart or sample, create its `README.md` in the same commit. Follow the established pattern: Purpose → Public surface → Configuration → Dependencies.
- Keep every `README.md` in sync with its implementation. During any refactoring — and **always** before opening a pull request — scan each affected `README.md` for outdated type, input or output names, missing or removed configuration options, stale dependency tables and inaccurate diagrams. Update it in the same change, never as a follow-up.
- **Major refactorings** (renames, moves, dependency-injection restructuring, type splits): update every `README.md` that mentions the old names in the same commit. Do not leave stale references behind.
- For changes spanning several projects, review all impacted `README.md` files before opening the pull request.
- **Only document what exists**: do not describe behaviour — encryption, resumability, deduplication, retry semantics, platform support — until the implementation and its tests or validation are in place.
- **Placeholders in examples**: examples must use synthetic values. Never include real credentials, tokens, connection strings, endpoints, hostnames, resource identifiers, device addresses or personal data.
- **Configuration examples**: components exposing strongly typed configuration should include a `## Configuration Examples` section with snippets progressing from minimal to fully configured, giving consumers copy-paste-ready templates.
- **Markdown tables**: separator rows use spaces around pipes to match the header and data rows (`| --- | --- |`, not `|---|---|`). This prevents MD060 (table-column-style) warnings.

### Structure and Accessibility

Apply to every file named `README.md`, wherever it lives — repository root, project, sample, chart or documentation sub-folder. These rules are specific to `README.md` and do not apply to other Markdown files.

- **Exactly one `# H1`**, as the first content line, naming the repository, project or module. Never repeat the H1 lower down and never open with `##`.
- **Never skip heading levels**: `#` → `##` → `###` in order. Skipping breaks outline extraction and MD001.
- **Lead with a one- or two-sentence summary** directly under the H1 stating what the thing is and who it is for. Search engines and package registries surface this as the description.
- **Keep the H1 aligned with the package identity** so the README title, the packaging metadata description and the published registry listing agree.
- **Descriptive link text**: never `click here`, and never a bare URL where a phrase reads better.
- **Alt text on every image** describing the content rather than the file (`![Service dependency graph](…)`, not `![diagram](…)`).
- **Unique headings within a file** so generated anchors resolve predictably.
- **No YAML front matter**: front matter belongs only to Copilot customisation files (`*.instructions.md`, `*.prompt.md`, `*.agent.md`) and to GitHub issue and pull request templates, which require it. Never add a `title:`, `description:` or `author:` block to a `README.md` or to any other documentation Markdown; GitHub renders it as a table above the content rather than as a heading, leaving the page with no `<h1>`. The `# H1` and the summary sentence beneath it already carry the title and the description.

## Generated Reference Documentation

Where a tool generates interface documentation (inputs, outputs, providers, resources, API surface) into a `README.md`:

- Generate it; never hand-maintain the generated tables.
- Use the source declarations' own description attributes as the canonical text. Treat comment scraping only as a fallback for declarations without a description.
- Preserve the generator's `BEGIN`/`END` marker comments around the generated block, and never edit between them.
- Regenerate after any change to the public interface or to version constraints, and commit the regenerated output in the same change.
- Keep the generator version pinned identically in the development container and in the pre-commit configuration.
- Enforce drift in both pre-commit and CI: uncommitted generated output is a failed check, not a cosmetic difference.

## Mermaid Diagrams

Use Mermaid diagrams in `README.md` files to visualise complex relationships and flows. Choose the diagram type that matches the relationship, not the technology.

### Diagram Type Selection

- **`flowchart`**: sequential processes — data flow, event flow, orchestration, build and deployment pipelines.
  - Direction: `TD` for vertical flows, `LR` for wide pipelines.
- **`graph`**: non-sequential relationships — dependencies, references, hierarchies.
  - Direction: `TD` for dependency trees, `LR` for peer relationships.
- **`classDiagram`**: type hierarchies — inheritance (`<|--`), composition (`*--`), aggregation (`o--`), association (`-->`), dependency (`..>`).
- **`sequenceDiagram`**: time-ordered interactions between components — calls, asynchronous operations, timing.

### Standard Headings

Use these heading patterns before a diagram:

| Heading | Use For |
| --- | --- |
| `## Data Flow` | How data moves through the system |
| `## Event Flow` | Event-driven processing: publish/subscribe, channels, streams |
| `## Service Architecture` | How runtime components interact |
| `## Dependency Graph` | Package, module and project dependencies and references |
| `## Application Hierarchy` | Nested application or component structures |
| `## Class Hierarchy` | Type structures and inheritance trees |
| `## Deployment Flow` | Build, release and deployment pipelines, and their call chains |
| `## Configuration Hierarchy` | Nested configuration objects |

### Styling Guidelines

- **Subgraphs**: group related components, stages or layers.
- **Custom styling**: define `classDef` to distinguish categories that matter to the reader, such as components this repository owns versus external ones it only consumes.
- **Node shapes**:
  - `[ ]` rectangle (default) — components, jobs, steps
  - `([ ])` stadium — entry and exit points, reusable or top-level units
  - `[( )]` cylinder — databases, storage, state backends
  - `{ }` diamond — decision points
  - `(( ))` circle — events

### Synchronisation

- Diagrams must stay in sync with the code, configuration or pipeline they describe.
- When renaming a component, input or output, update the corresponding diagram nodes in the same change.
- When adding or removing a dependency, update the dependency graph in the same change.
- Review every `README.md` diagram before opening a pull request.

## Markdown Linting

The `lint` job in CI, which runs `pre-commit`, is the authoritative gate. Reproduce it locally before pushing rather than discovering failures in CI.

- **Run from the repository root** so the repository's own linter configuration is auto-discovered. Passing files from a parent directory silently skips that configuration and produces false MD025 failures.
- **Prefer native `pre-commit`** when Python is available: `pre-commit run --all-files`, or `pre-commit run markdownlint --all-files` to scope to Markdown.
- **No local Python? Run `pre-commit` in a container.** Build once with `pre-commit` and Node baked in, then mount the repository. Pin the `pre-commit` version to the one CI uses, and pass a named cache volume so hook environments survive between runs:

  ```bash
  docker build -t pre-commit-runner:local - <<'EOF'
  FROM python:3.12-slim
  RUN apt-get update \
      && apt-get install -y --no-install-recommends git nodejs npm \
      && rm -rf /var/lib/apt/lists/*
  RUN pip install --no-cache-dir pre-commit==3.7.1
  WORKDIR /src
  EOF

  docker run --rm \
      -v "$PWD:/src" \
      -v pre-commit-cache:/root/.cache/pre-commit \
      pre-commit-runner:local \
      sh -c 'git config --global --add safe.directory /src && pre-commit run --all-files'
  ```

  The `safe.directory` line is required because the mounted repository is owned by a different UID inside the container.

- **If the image build fails on `pip install` with an SSL handshake error**, the network is blocking the PyPI package CDN. The index itself may still resolve, so packages appear reachable while none can be downloaded. Neither `--trusted-host` nor a different index fixes this; it is a middlebox rejecting the CDN's TLS. Fall back to invoking the underlying linter directly.
- **Direct linter fallback** — read the version and arguments from the repository's own `.pre-commit-config.yaml` rather than assuming, because they differ between repositories:

  ```bash
  npx --yes markdownlint-cli@<pinned-version> --disable MD013 --disable MD034 -- "**/*.md"
  ```

- **Honour `exclude:` blocks manually.** Invoking the linter directly bypasses any `exclude:` regex in `.pre-commit-config.yaml`, so generated or vendored files that the real gate skips will report failures. Check for an `exclude:` before treating a direct-invocation failure as real.
