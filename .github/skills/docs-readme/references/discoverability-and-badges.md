# README Discoverability and Badges

Apply when creating or auditing a README. The
[README instructions](../../../instructions/markdown.readme.instructions.md) own the always-on README
structure and content boundaries.

## Public Primary README Discoverability

Apply these principles to a public repository's primary README, not as an SEO checklist for private
repositories or every internal guide:

- Keep the actual product identity in the H1. In the opening summary, naturally name the product
  category, important platform or ecosystem, problem solved and intended users. Explain unfamiliar
  names and acronyms instead of assuming readers already know the project.
- Use terms potential users would search for in useful prose, descriptive headings, examples and
  link text. Prefer a concrete capability description over vague marketing claims.
- Keep essential explanations as searchable text, not only in badges, screenshots or diagrams.
  Link relevant public package listings and documentation with meaningful text.
- Keep the README's description consistent with current repository and registry metadata. Flag
  inaccurate descriptions, topics or website links, but do not change GitHub settings without
  authorization.
- Do not add keyword lists, repeated synonyms, hidden text, frontmatter or HTML metadata as an SEO
  workaround. GitHub controls the page metadata; README edits cannot guarantee indexing or ranking.

## Badges and External Destinations

- Use a small set of useful live badges, not manually maintained version or coverage graphics.
  Put repository-wide badges after the summary and per-package versions in the collection catalogue.
- Make badges clickable: package versions lead to the matching package, Marketplace badges to the
  verified listing, CI status to its workflow, and analysis metrics to the matching project or metric.
- Match alt text, metric, destination and branch. Code smells are not coverage, and a Quality Gate
  is not a test result. Do not imply analysis or Marketplace publication exists without evidence.
- Resolve package IDs, listings, workflow paths and analysis keys from authoritative configuration
  or verified service metadata, not guessed naming conventions. Verify both image and link targets.
- For private repositories, check whether a badge is accessible to its audience and whether its URL
  or image request discloses identifiers to an external service. Do not add credentials, proxy
  tokens or private coordinates to public badge services; omit an unsuitable badge.
