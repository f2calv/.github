# Repository Layout

Repositories share one layout regardless of language. Apply it when creating or bootstrapping a
repository, and when auditing one for drift.

## Root and Folders

- **Root files**: `README.md`, `LICENSE`, `GitVersion.yml`, `.editorconfig`, `.gitattributes`,
  `.gitignore` and `.pre-commit-config.yaml`.
- **Source code** lives under `src/`. GitHub Action repositories keep `action.yml` at the root.
- **Tooling** lives in dot-prefixed folders: `.github/` (workflows, instructions, Dependabot),
  `.scripts/`, `.devcontainer/`, `.docker/`, `.config/` and `.vscode/`.
- **Documentation** beyond the root `README.md` is Markdown under `docs/`.
- `.editorconfig` is the single source of truth for indentation, line endings and analyzer or
  formatting rules; `GitVersion.yml` drives semantic versioning.
- `.gitattributes` standardises line endings across Windows and Linux:

  ```gitattributes
  * text=auto eol=lf
  *.{cmd,[cC][mM][dD]} text eol=crlf
  *.{bat,[bB][aA][tT]} text eol=crlf
  ```

## Bootstrapping From Exemplars

- When the user names existing repositories as exemplars and the conventions or files to carry over,
  treat them and the request as the approved design. Inspect their current files and reproduce the
  applicable conventions, changing only the new repository's identity and genuinely different
  behaviour.
- Create no planning receipt, such as `.azure/requirements.json`, `project-plan.md`, a questionnaire
  or a manifest, unless the user explicitly asks for one. The conversation remains the source of
  truth.
- Copy conventions, structure and public-safe defaults, never repository-specific identifiers,
  credentials, deployment coordinates or behaviour the new repository does not implement yet.
- Verify the resulting file inventory against the exemplars and document intentional omissions
  rather than filling them with speculative placeholders.
