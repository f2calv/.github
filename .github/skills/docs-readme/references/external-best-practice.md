# Using External Best Practice

Which external guidance informs README decisions, and how it ranks against the shared instructions.

## Using External Best Practice

Use public guidance as evidence, not a checklist to copy. Prefer current platform documentation
over blog templates, popularity rankings or historical conventions:

| Source | Use it to verify |
| --- | --- |
| [GitHub README guidance](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-readmes) | Reader needs, README discovery, built-in navigation and link behavior |
| [NuGet README guidance](https://learn.microsoft.com/en-us/nuget/nuget-org/package-readme-on-nuget-org) | Package presentation, supported Markdown, image-host restrictions and preview behavior |
| [GitHub Marketplace guidance](https://docs.github.com/en/actions/how-tos/create-and-publish-actions/publish-in-github-marketplace) | Action listing requirements and the metadata used by the listing |
| [GitHub community defaults](https://docs.github.com/en/communities/setting-up-your-project-for-healthy-contributions/creating-a-default-community-health-file) | Supported inherited files, visibility and local override behavior |
| [Google SEO starter guide](https://developers.google.com/search/docs/fundamentals/seo-starter-guide) | Durable people-first discoverability principles, not GitHub-specific metadata controls or ranking promises |

Distinguish platform requirements from optional recommendations. Check the relevant current source
when a decision depends on renderer support, publication requirements, image hosts or inherited-file
behavior; do not freeze those capabilities or an allowlist in this skill. If verification is
unavailable, report the uncertainty rather than asserting an old limitation as current fact.

Adopt advice only when it helps this repository's readers and fits its delivery type and shared
conventions. Do not add a manual table of contents, badge wall, contributor roster, roadmap,
screenshots or redundant support sections merely because a popular template includes them.
GitHub already provides an outline; add in-document navigation only when the document or another
rendering destination benefits. Keep extended documentation under `docs/` rather than introducing
a wiki just because external guidance suggests one.
