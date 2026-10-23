# Partial Retirement Handoff

This is a synthetic reporting example, not evidence that any repository was inspected or archived.
Use it after an authorized retirement workflow to distinguish requested work, verified outcomes,
blocked work and separately unapproved deletion.

## Example Handoff

Scope: three explicitly approved synthetic repositories. Results below are scenario assumptions
that must be replaced with current evidence in a real report.

| Target | Outcome | Evidence or blocker | Next action |
| --- | --- | --- | --- |
| `owner/example-retired` | Archived and read back as archived | Final retirement PR merged; notice on default branch; open work and active-run gates clear | Preserve local clone and downloadable packages through agreed retention |
| `owner/example-pending` | Not archived | Human-authored PR still needs an approved disposition | Owner reviews the PR; do not close it as automated cleanup |
| `owner/example-unverified` | Archive request sent, final state unverified | Follow-up API read failed | Re-read remote state before retrying; do not claim success or resend blindly |

Totals: **one verified archive, one blocked before archival, one unverified outcome**. This is not
"three archived" and not "one deleted". A failed verification does not prove that the preceding
mutation failed.

### Preserved Surfaces

* Releases and packages: intentionally retained for existing consumers; not deleted.
* External analysis projects: retained; archival does not remove their history.
* Security findings: unchanged by archival; unresolved alerts are not described as fixed.
* Local clones and workspace entries: untouched; local deletion was not authorized.

### Evidence Still Required in a Real Handoff

Record the final retirement PR URL and merge commit, verified default-branch notice, description
update, open issue/PR dispositions, active-run state, and post-archive read for each successful
target. Include current security/quality-gate findings and any unavailable analysis limitation.
Use verified same-visibility links; this example intentionally invents no PR numbers or commit IDs.

For the blocked target, identify the human decision still needed and who owns it. For the
unverified target, preserve the operation's uncertainty until a successful read resolves it.
Do not let success on an independent target conceal the failure.

## Stop and Recovery Decisions

| Observation | Correct response |
| --- | --- |
| Archive call succeeded but read-back failed | Report unverified; inspect state before retry |
| Open human work or an active workflow remains | Stop archival for that target |
| Required check or quality gate is absent/pending/failing | Do not merge the retirement PR or archive early |
| Local clone has unpushed/uncommitted work | Preserve it and ask before discarding anything |
| User approved archival only | Do not delete clones, packages, releases, analysis projects or workspace entries |
| Repository is already archived but a final notice is missing | Report incomplete retirement; obtain authorization for the corrective workflow |

Never put wildcard deletion or a bulk unchecked archive command in a report template.
The owning skill supplies the executable workflow and approval gates; this example supplies the
output shape and evidence distinctions only.
