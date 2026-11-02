# Shared Workflow Authoring

Rules for changing the shared-workflows repository or an Action repository, beyond the always-on
[GitHub Actions instructions](../../../instructions/github.actions.instructions.md).

## File Naming

- A shared (cross-repository) workflow has a non-underscore filename with an `_`-prefixed `name:`,
  for example the file `app-build.yml` declaring `name: _app-build`.
- A local reusable workflow has an underscore-prefixed filename, such as `_publish-artifacts.yml`,
  distinguishing it from top-level entry-point workflows.

## Helm Packaging Coordinates

For the shared Helm packaging workflow, pass the full final OCI coordinate as `chart-repository`,
such as `${{ github.repository_owner }}/charts/example`. The workflow pushes to
`dirname(chart-repository)` and derives the package name from the `chart-path` directory basename,
so that basename, `Chart.yaml` `name` and the coordinate's final segment must match. Never insert
the source repository name into the artifact path; that produces nested coordinates such as
`<owner>/<source-repository>/<chart-name>`.

## Release Validation

Action and reusable-workflow repositories validate before release that their README consumer
examples reference the exact floating major tag computed by GitVersion, such as `owner/action@v2`
or `owner/workflows/.github/workflows/build.yml@v1`; `@v2.1` must not satisfy an `@v2` check.
Include that validation job in the release job's `needs`, and pass its validated
`major.minor.patch` values to the release step rather than a `FullSemVer` value that may contain
build metadata.
