# Contributing

Contributions are welcome through an issue-first workflow. Discuss the problem and intended scope
before investing in an implementation so maintainers and contributors share the same expectations.

## Create Or Find An Issue

1. Search the repository's open and closed issues for an existing report or proposal.
2. If none exists, create an issue describing the problem, expected outcome and relevant context.
3. Discuss the approach in the issue when the change is substantial or has design trade-offs.

Do not open a pull request without a corresponding issue. Suspected security vulnerabilities are
the exception: report them privately through the repository's Security tab rather than a public
issue.

## Make The Change

1. Start from the repository's default branch and create a focused branch for the issue.
2. Follow the repository's instructions, established patterns and formatting rules.
3. Keep the change limited to the agreed issue scope.
4. Add or update tests and documentation when behavior or public interfaces change.
5. Run the repository's documented formatting, linting, build and test checks.
6. Never include credentials, personal data or private-system details in a public change.

## Open The Pull Request

1. Link the issue in the pull request description using `Closes #123` or the appropriate issue
   number.
2. Explain what changed, why it changed and how it was validated.
3. Call out breaking changes, migrations, operational follow-up and checks that were not run.
4. Keep unrelated changes in separate issues and pull requests.
5. Address review feedback and ensure all required checks pass before merge.
