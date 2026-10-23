# [Bug]: Explicitly disabled export still produces an output file

## Report

### What happened?

Synthetic reproduction: an export configured with `enabled: false` still writes its output.
This prevents a caller from disabling export without removing the configuration entirely.
The cause has not been established; boolean-default handling is a hypothesis, not a confirmed fix.

### How can we reproduce it?

1. Use the synthetic exporter version listed below with a temporary output directory.
2. Configure `export.enabled` as the boolean `false`.
3. Run one export with an empty input collection.
4. Observe that an output file is created despite the disabled setting.

### What did you expect?

No output file should be created when export is explicitly disabled. Omitting the setting should
retain the documented default. Cover both cases before changing default handling.

### Version

Synthetic example version `1.2.3`; replace with the actual affected immutable release or commit.

### Environment

Scenario assumptions: .NET 10, Linux x64, local temporary filesystem, no external services.
Replace these assumptions with the actual reproduction environment before submission.

### Relevant logs

No logs supplied. Attach only redacted evidence from an actual reproduction.

### Submission checks

- [ ] I searched existing issues and did not find a duplicate.
- [ ] I removed credentials, personal data and private-system details.
