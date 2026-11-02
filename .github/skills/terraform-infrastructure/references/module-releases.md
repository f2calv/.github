# Module Releases

How a reusable child module versions, publishes breaking changes and gates pull requests.

## Module Versioning

- Continuous integration bumps the patch version on every pull request, so a `+semver:` directive is only needed to request a larger increment than a patch.
- Before adding a `+semver:` directive, inspect every commit between the merge base with `origin/main` and `HEAD`. A branch must contain at most one directive, placed in the commit that introduces the versioned behaviour.
- Use `+semver:feature` for breaking changes, including removed or renamed inputs, outputs and resource addresses. A compatible change needs no directive.
- After the branch is complete, run GitVersion with the repository's `GitVersion.yml` and verify the final numeric major, minor and patch result.
- Publish releases as plain `X.Y.Z` tags with no prefix and no moving aliases, per the GitHub instructions, and set the release-versioning workflow inputs accordingly.
- Pin the module source example in `README.md` to the expected final immutable tag, excluding feature-branch pre-release labels, and update it in the same change. Treat a mismatch between the README source ref and the expected release tag as a CI failure.

## Breaking Changes

Adding a required variable, renaming a resource, or removing a resource is a breaking change for every consumer.

- Publish breaking changes as a new major release without in-module compatibility shims. Consumers migrate explicitly when they update their pinned tag.
- Document any state migration command consumers must run before applying the new major release.
- Require callers to pin to a tag. A caller tracking a branch ref inherits breaking changes silently on their next `init`.
- Record the change in the commit message with a `BREAKING CHANGE:` footer.

## Continuous Integration

- Pull requests must run `terraform fmt`, a backend-free `terraform init` and `terraform validate`, and all three must pass without cloud credentials. With no backend declared, `-backend=false` is sufficient.
- Require the validate job as a status check on `main`, alongside the repository-wide lint and versioning checks.
- Configure Dependabot's `terraform` ecosystem for the module directory, keep provider ranges broad within the current supported major, and validate automated provider-major updates through the same pull request checks as manually authored changes.
