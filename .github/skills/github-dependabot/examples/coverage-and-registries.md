# Dependabot Coverage and Registry Examples

These are independent scenarios, not two files to install side by side. Adapt the selected
[multi-root configuration](../templates/multi-root.yml) or
[private NuGet configuration](../templates/private-nuget.yml) into the repository's single
`.github/dependabot.yml`. Preserve existing policy and add only entries supported by owned manifests.

## Multi-Root Repository

The first template assumes this evidence has already been inspected:

| Evidence | Updater | Roots covered |
| --- | --- | --- |
| Workflows containing remote `uses:` references | `github-actions` | `/` |
| Root pre-commit configuration with remote hooks | `pre-commit` | `/` |
| Root central package file and owned .NET projects beneath `src/` | `nuget` | `/` |
| Independent `src/web/package.json` and `src/admin/package.json`, each with its own lockfile | `npm` | `/src/web`, `/src/admin` |
| Owned Dockerfiles beneath `.docker/web/` and `.docker/worker/` | `docker` | `/.docker/web`, `/.docker/worker` |

There is no root npm workspace in this scenario. If a root workspace owns resolution and its
lockfile, configure that workspace instead; do not transplant the two independent-root entries.
The example assumes the Microsoft.Extensions packages intentionally move together within a release
line, so their minor/patch updates are grouped. Major updates are not ignored; they remain separate
for compatibility review. Remove the group when that coupling is not true.

The weekly policy is shared across each pair of roots, so one `directories` entry is sufficient.
Use separate entries only when their schedules, registries or other policies differ. Do not add a
second npm entry for `/src/web`, or a glob that also matches it. Paths must not overlap across
entries for the same ecosystem and target branch. Different ecosystems can legitimately use `/`.

Do not infer an updater from an extension alone. For example, a `global.json` that only selects MTP
has no SDK version for `dotnet-sdk` to update. Neither a Dev Container image nor its Features are
present in this scenario; add their applicable coverage only when the repository actually owns them.

## Private NuGet Feed

The second template shows a third-party feed using username/password authentication. It is not
needed merely because a package is private: first check whether GitHub-hosted packages can use
automatic repository access, or whether the provider supports an appropriate OIDC configuration.

Three independent pieces must agree:

1. The application's existing NuGet source configuration points to the intended feed.
2. The top-level `registries.example-feed` entry declares that feed and its authentication.
3. The NuGet update entry explicitly includes `example-feed` under `registries`.

Defining credentials at the top level alone does not opt every update job into using them.
Conversely, the registry declaration does not add a missing source to the application's NuGet
configuration. Keep the source URL identical between the two and use the provider's actual
authentication mechanism; do not assume every token belongs in the password field.

Create the named values as **Dependabot secrets**, not only Actions secrets. Grant only package-read
access. This template contains secret references, never secret values; local and CI restore
authentication remains a separate concern. It does not enable external dependency code execution.

Registry URLs and package identities can themselves be confidential. Use this configuration in a
private consumer or with a registry endpoint explicitly approved for publication. Never replace
the synthetic URL with private infrastructure details in a public repository.

If the multi-root scenario also needs this feed, merge the top-level registry declaration and add
`registries: [example-feed]` to its **existing** NuGet entry. Do not append a duplicate NuGet `/`
entry or discard its package-family group.

## Acceptance Checks

* Parse the selected YAML and require `version: 2`, a non-empty update list, and exactly one of
  `directory` or `directories` per entry.
* Rebuild the coverage matrix from actual manifests. Every listed root must exist and contain an
  updateable dependency; every required root must be covered once.
* Resolve globs before checking overlap; comparing pattern strings is insufficient.
* Check every per-update registry name against the top-level declarations and confirm required
  Dependabot secrets/access grants without printing their values.
* After adoption, inspect GitHub's update logs for each ecosystem. Local parsing and fixture
  assertions prove neither authentication nor resolver success.

See the [current options reference](https://docs.github.com/en/code-security/reference/supply-chain-security/dependabot-options-reference)
and [private registry guidance](https://docs.github.com/en/code-security/how-tos/secure-your-supply-chain/manage-your-dependency-security/configure-access-to-private-registries)
before changing schema-sensitive options.
