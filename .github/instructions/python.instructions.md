---
description: 'Python coding conventions for style, typing, errors, logging, configuration, concurrency, testing, documentation, performance, dependencies and packaging.'
applyTo: '**/*.py,**/pyproject.toml,**/uv.lock,**/.python-version'
---

# Python

## Style (enforced by `ruff` and `mypy`)

- **`ruff format` is authoritative.** Never hand-format Python source; run `ruff format .` before committing. CI fails on `ruff format --check .`.
- **`ruff check` must pass.** Select broadly (`select = ["ALL"]`) and justify each entry in `ignore`. Prefer fixing the code over a suppression; when one is genuinely warranted, scope it to the narrowest line with `# noqa: RULE` and say why.
- **`mypy --strict` must pass.** Every function, parameter and return value is annotated, including `-> None`. An untyped function body is a defect, not a style preference.
- **Indentation**: 4 spaces, LF line endings, final newline. Line length is set once in `pyproject.toml` and honoured by both formatter and linter.
- **Naming**: `snake_case` for modules, functions, methods and variables; `PascalCase` for classes and enums; `SCREAMING_SNAKE_CASE` for module-level constants.
- **Module-per-concern**: one focused responsibility per module (`config.py`, `telemetry.py`, `worker.py`). Modules are the Python analogue of the one-type-per-file rule used in the .NET conventions - do not accumulate unrelated responsibilities in one file.
- **`__main__.py` is wiring only**: load configuration, install logging, register signal handling, hand off to a worker, map terminal failures to exit codes. Business logic belongs in a module.
- **Visibility is deliberate**: prefix helper functions, classes and attributes that are not imported elsewhere with a single underscore. Module-level constants are exempt. Do not rely on `__all__` as a substitute for naming intent.
- **Modern syntax only**: built-in generics (`list[str]`, `dict[str, int]`), `X | None` rather than `Optional[X]`, `StrEnum` for closed string sets, and structural pattern matching where it reads more clearly than a chain of `elif`.
- **`from __future__ import annotations`** at the top of every module, with type-only imports inside `if TYPE_CHECKING:` so runtime import cost and cycles are avoided.
- **Import ordering** is ruff's (`std` / third-party / first-party, each group separated by a blank line). Import names, not whole modules, unless the module qualifier aids readability.
- **Dataclasses over ad-hoc dicts**: use `@dataclass(frozen=True, slots=True)` for immutable value and configuration records. `frozen` prevents accidental mutation; `slots` removes the per-instance `__dict__`.
- **`pathlib.Path` for filesystem paths**, never string concatenation or `os.path`.
- **Context managers for owned resources**: files, sockets, locks and clients are acquired with `with` / `async with`, never opened and closed by hand.
- **Prefer comprehensions and generator expressions** over `map`/`filter` chains or index loops, and stop when the comprehension becomes harder to read than an explicit loop.
- **Early return over nesting.** Handle the failure and `return`; keep the happy path at the left margin.
- **Never use a mutable default argument.** Default to `None` and construct inside the function.

## Error Handling

- **Catch only what you can handle, translate or enrich.** A bare `except:` is forbidden, and `except Exception` needs a comment justifying the breadth.
- **Never silently discard an exception.** `except ...: pass` requires an explicit comment explaining why the failure is genuinely uninteresting.
- **Preserve the cause**: always `raise DomainError(message) from error`. A bare `raise X(...)` inside an `except` block discards the original traceback.
- **Define domain exceptions at boundaries** (`ConfigurationError`, `TelemetryError`), deriving from the closest built-in (`ValueError`, `RuntimeError`) so existing handlers still behave sensibly.
- **Assign the message to a local before raising** so the exception constructor call stays short and the message is greppable.
- **Keep messages actionable and safe**: name the setting, file or operation that failed, never credentials, tokens, connection strings or personally identifying values.
- **`sys.exit` belongs to `main` alone.** Reusable modules raise; only the entry point maps an exception to an exit code.
- **Do not use exceptions for expected absence.** Return `None`, a sentinel or a result object where that makes the contract clearer.

## Logging

- **The standard library `logging` module is the logging framework.** Never use `print` for application diagnostics.
- **One logger per module**: `logger = logging.getLogger(__name__)` at module scope. Application code never configures handlers.
- **Structured fields, not interpolated strings.** Pass varying values through `extra=`, keeping the message itself a constant so events group correctly. Never build a message with an f-string or `%` formatting.
- **Field names are `snake_case`** and match sibling repositories' names where the concept is shared (`git_repository`, `interval_seconds`, `process_architecture`).
- **Field names must avoid the reserved `LogRecord` attributes** (`message`, `args`, `name`, `module`, `levelname` and friends). `logging` refuses to overwrite them, and the failure is a confusing runtime error rather than a type error.
- **Handler setup lives in one place** (`telemetry.py`) and is installed exactly once from the entry point.
- **Use `logger.exception(...)`** inside an `except` block so the traceback is captured; `logger.error(...)` discards it.
- **Verbosity via a `LOG_LEVEL` environment variable**, defaulting to `info`.
- **Never log secrets or personal data**: tokens, authorisation headers, connection strings, signed URLs, full local paths and personally identifying values must never reach a sink.

## Configuration

- **Layered, defaults-then-file-then-environment.** Environment variables win, so a container can be reconfigured without rebuilding the image.
- **Every setting has a default**, so the application runs with no configuration file and no environment variables present.
- **Parse into a typed record.** Bind once into a frozen dataclass; never scatter `os.environ` reads through the code base.
- **Accept an injected environment mapping** (`environ: Mapping[str, str] | None = None`, defaulting to `os.environ`) so configuration loading is testable without mutating process state.
- **Keys are `snake_case`** in both the file and the environment, and the section separator is `__` (`APP__INTERVAL_SECONDS`), matching the sibling .NET, Go and Rust repositories.
- **Validate at startup.** Check types, ranges, required values and closed sets as configuration is loaded, and abort the process with a clear message. A configuration error must never surface later as a runtime surprise.
- **Coerce deliberately.** Environment variables arrive as strings; convert and validate explicitly rather than relying on truthiness, and reject `bool` where an `int` is expected.

## Concurrency and Shutdown

- **Register SIGINT and SIGTERM in the entry point**, which is the only place Python permits signal handler installation on the main thread.
- **Cancellation is explicit.** Pass a `threading.Event` (or an `asyncio.Event` / `CancellationToken` equivalent) into long-running work, and loop on it so shutdown is prompt.
- **Use `event.wait(timeout)` for interruptible delays**, never `time.sleep` inside a cancellable loop - a sleeping worker cannot observe a shutdown request.
- **Every thread and task has a defined exit.** If you cannot say what stops it, do not start it, and never leave a non-daemon thread without a join.
- **Do not hold a lock across I/O or a cancellation wait.** Keep critical sections small and prefer queues over shared mutable state.
- **Flush and shut down owned providers** (telemetry exporters, clients, pools) in a `finally` block so buffered data is not lost on exit.
- **Remember the GIL.** Threads suit I/O-bound work; use `multiprocessing` or a native extension for CPU-bound work rather than expecting threads to scale.

## Testing

- **`pytest` is the test framework.** Tests live in `tests/`, mirroring the package layout.
- **Plain `assert`**, not `unittest` assertion methods - pytest rewrites them to produce useful failure output.
- **Test names describe the behaviour**, not the function: `load_falls_back_to_defaults_when_file_missing`, not `test_load`.
- **Arrange/Act/Assert**, separated by blank lines. One behaviour per test.
- **`@pytest.mark.parametrize`** for anything with more than one interesting input, rather than a loop inside a single test.
- **Use the built-in fixtures** (`tmp_path`, `monkeypatch`, `caplog`, `capsys`) instead of hand-rolled setup and teardown; they restore state automatically.
- **Never mutate `os.environ` directly** in a test. Use `monkeypatch.setenv` or pass an explicit environment mapping.
- **No shared mutable module-level state between tests.** Each test must be independently repeatable and order-independent.
- **Assert on public behaviour**, not private helpers, unless the helper carries genuinely tricky logic.
- **`assert` is stripped under `python -O`.** Never use it for runtime validation in application code - only in tests.

## Documentation

- **Docstrings on every public module, class and function.** A module docstring is the first statement in the file.
- **First line is a single-sentence summary** in the imperative mood, ending with a full stop. Further detail goes in following paragraphs after a blank line.
- **Document the contract, not the implementation**: constraints, raised exceptions, units and defaults. Restating the code in prose is noise.
- **Do not repeat type information** already carried by annotations.
- **Do not delete hyperlinks** to blog posts, issues or answers when refactoring a comment - move them into the docstring.

## Performance

- **Measure before optimising.** Profile with `cProfile` or a benchmark before any micro-optimisation; prefer clear code until measurement says otherwise.
- **Avoid work in hot loops**: hoist attribute lookups, reuse buffers, and build strings with `str.join` rather than repeated concatenation.
- **Generators over lists** when the whole sequence is not needed at once, particularly when streaming records.
- **Prefer built-ins and the standard library**, which are implemented in C, over hand-written equivalents.
- **Avoid unbounded cardinality** in log fields, metric labels and caches. Serialisation costs are paid even when the surrounding logic is trivial.

## Dependencies and Packaging

- **Prefer the standard library.** Every dependency is install time, image size and supply-chain surface; add one only when it removes meaningful complexity.
- **`pyproject.toml` is the single manifest.** Declare runtime dependencies under `[project]` and tooling under `[dependency-groups]` so development-only tools stay out of the production image.
- **Pin the interpreter** in `.python-version` and in `requires-python`, and target the same version in the linter and type checker so all three agree.
- **The lock file is committed**, and CI installs with a locked, no-update sync so the dependency graph cannot silently drift.
- **Runtime dependency versions are pinned exactly**; the lock file records the full resolution and Dependabot proposes the updates.
- **Run tooling inside the development container.** Do not install interpreters or packages onto the host.
