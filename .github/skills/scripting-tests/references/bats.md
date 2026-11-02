# bats-core

How to write and run bats-core tests for Bash scripts. The always-on rules are in the
[Bash instructions](../../../instructions/shell.bash.instructions.md#testing).

## Layout and Libraries

- Name test files `<script>.bats` in the script's test folder, starting with `#!/usr/bin/env bats`.
- Load [bats-support](https://github.com/bats-core/bats-support) and
  [bats-assert](https://github.com/bats-core/bats-assert) with `bats_load_library`, which searches
  `BATS_LIB_PATH`; never vendor them into the repository or load them by relative path.
- Declare `bats_require_minimum_version 1.5.0` at file level when using `run` flags such as
  `--separate-stderr` or an expected status (`run -1`).

## Writing Tests

- Build each test's workspace under `$BATS_TEST_TMPDIR` in `setup()`, which bats deletes after the
  test. Copy fakes into `$BATS_TEST_TMPDIR/bin`, `chmod +x` them and prepend that folder to `PATH`.
- Unset environment variables the script reads in `setup()`, so a value from the developer's shell
  never leaks into a test.
- Run the script with `run`, then assert with `assert_success`, `assert_failure 1`,
  `assert_output --partial`, `assert_output --regexp` and `assert_line --index`. Use
  `run --separate-stderr` and test `$stderr` when the message must go to stderr.
- Write `assert_output --regexp` patterns in POSIX ERE: `[[:space:]]` and `[0-9]`, never `\s` or
  `\d`, which glibc accepts but musl, used by the bats container image, does not. `.` matches
  newlines, so one pattern can span table rows.
- Lint the test file with `shellcheck -s bash`, as for any script.

## Running

Without bats installed, use the official image, which ships bats-support, bats-assert and bats-file
under `/usr/lib/bats`. Add any tools the script needs:

```bash
docker run --rm -v "$PWD:/code" -w /code --entrypoint bash bats/bats:1.14.0 -c \
  'apk add --quiet --no-cache jq && BATS_LIB_PATH=/usr/lib/bats bats tests/bash'
```

## Continuous Integration

GitHub-hosted Ubuntu runners include `shellcheck` and `jq`.

```yaml
#bats-action publishes no floating major tag, so the full release is pinned.
- id: setup-bats
  uses: bats-core/bats-action@4.1.0
  with:
    detik-install: false
    file-install: false

- name: bats tests/bash
  env:
    BATS_LIB_PATH: ${{ steps.setup-bats.outputs.lib-path }}
    TERM: xterm
  run: bats tests/bash
```
