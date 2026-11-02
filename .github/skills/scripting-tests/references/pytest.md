# pytest

How to write and run pytest suites for Python scripts and packages. The always-on rules are in the
[Python instructions](../../../instructions/python.instructions.md#testing).

## Layout and Dependencies

- Put tests in `tests/` mirroring the package, or beside the script's other tests, as
  `test_<module>.py`. Configure discovery in `pyproject.toml` under `[tool.pytest.ini_options]`
  with `testpaths` and `addopts = "-ra --strict-markers"`.
- Declare pytest, ruff and mypy with exact pins in a `[dependency-groups]` group such as `test`,
  commit `uv.lock`, and add the `uv` ecosystem to Dependabot. Pin the interpreter in
  `.python-version` and `requires-python`, and target the same version in ruff and mypy.
- Ignore `.venv/`, `.pytest_cache/`, `.ruff_cache/` and `.mypy_cache/`.

## Writing Tests

- Use plain `assert`, Arrange/Act/Assert separated by blank lines, and one behaviour per test.
- Use `tmp_path`, `monkeypatch`, `capsys` and `caplog` instead of hand-written setup and teardown.
  Never mutate `os.environ`; build an explicit environment mapping for subprocesses instead.
- Run a script under test as `subprocess.run([sys.executable, script, *arguments], capture_output=True,
  text=True, env=env, check=False)` and assert on `returncode`, `stdout` and `stderr`.
- For fake executables, copy a script into `tmp_path / "bin"`, `chmod(0o755)` it and prepend that
  folder to `PATH` in the subprocess environment. Shebang fakes run on Linux and macOS only; mark
  such tests or run them in CI on Linux.
- Wrap repeated invocation in a small frozen dataclass fixture (`run`, `ok`, `fails`) so each test
  states only its arguments and assertions.
- Prefer `@pytest.mark.parametrize` to loops for several interesting inputs.
- Test files keep the `ruff` `ALL` selection with narrow per-file ignores: `S101` for `assert`,
  `D103` because test names describe the behaviour, `PLR2004` for expected counts and `INP001`
  for test folders without `__init__.py`.

## Running

With uv available, from the repository root:

```bash
uv sync --group test --locked
uv run --no-sync ruff format --check && uv run --no-sync ruff check
uv run --no-sync mypy
uv run --no-sync pytest
```

Without a suitable interpreter on the host, run the same commands in a disposable container,
installing the pinned uv first and keeping the virtual environment outside the mount:

```bash
docker run --rm -v "$PWD:/repo" -w /repo -e UV_PROJECT_ENVIRONMENT=/tmp/venv python:3.11-slim \
  bash -c 'pip install --quiet uv==<pinned> && uv sync --group test --locked && uv run --no-sync pytest'
```

Bind mounts from Windows report every file as executable, so ruff's `EXE002` misfires there.

## Continuous Integration

```yaml
#setup-uv publishes no floating major tag, so the full release is pinned.
- uses: astral-sh/setup-uv@v10.3.3
  with:
    version: 0.13.6

- name: uv sync --group test --locked
  run: uv sync --group test --locked

- name: uv run pytest
  run: uv run --no-sync pytest
```

Run `ruff format --check`, `ruff check` and `mypy` as separate steps in the same job.
