"""Behaviour tests for the Python skill library helper.

These mirror the Pester scenarios in ``Invoke-SkillLibrary.Tests.ps1`` and the bats scenarios in
``bash/skill-library.bats`` so the three helper variants stay in parity. The helper runs as a
subprocess against the shared catalog fixtures, with a fake ``specify`` first on ``PATH``.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

import pytest

TESTS = Path(__file__).resolve().parents[1]
REPO = TESTS.parents[4]
SCRIPT = REPO / "src/skill-library-extension/scripts/python/skill_library.py"
FIXTURES = TESTS / "fixtures/helper"
CATALOG = FIXTURES / "catalog.json"
CHANGED = FIXTURES / "catalog-changed.json"
REGISTRY = ".specify/extensions/.registry"
MANAGE_HINT = "Manage skills with /speckit-skill-library instead of specify extension add, remove, enable or disable."


@dataclass(frozen=True, slots=True)
class Result:
    """Exit code and captured output of one helper run."""

    code: int
    stdout: str
    stderr: str


@dataclass(frozen=True, slots=True)
class Library:
    """Runs the helper in one workspace with the fake specify on PATH."""

    workspace: Path
    env: dict[str, str]

    def run(self, *arguments: str, catalog: Path = CATALOG) -> Result:
        """Run one helper command against a catalog fixture."""
        completed = subprocess.run(  # noqa: S603 - the helper under test with an argument list
            [sys.executable, str(SCRIPT), *arguments, "-CatalogUrl", str(catalog), "-Workspace", str(self.workspace)],
            capture_output=True,
            text=True,
            env=self.env,
            check=False,
        )
        return Result(completed.returncode, completed.stdout, completed.stderr)

    def ok(self, *arguments: str, catalog: Path = CATALOG) -> str:
        """Run a command that must succeed and return its output."""
        result = self.run(*arguments, catalog=catalog)
        assert result.code == 0, result.stderr
        return result.stdout

    def fails(self, *arguments: str, catalog: Path = CATALOG) -> str:
        """Run a command that must fail and return its error message."""
        result = self.run(*arguments, catalog=catalog)
        assert result.code == 1, result.stdout
        return result.stderr

    def log(self) -> list[str]:
        """Return the fake specify call log."""
        return (self.workspace / "specify.log").read_text(encoding="utf-8").splitlines()

    def state(self) -> dict[str, dict[str, dict[str, object]]]:
        """Return the helper's state file."""
        path = self.workspace / ".specify/extensions/.skill-library.json"
        data: dict[str, dict[str, dict[str, object]]] = json.loads(path.read_text(encoding="utf-8"))
        return data

    def write_registry(self, extensions: dict[str, dict[str, object]]) -> None:
        """Replace the Spec Kit registry."""
        document = {"schema_version": "1.0", "extensions": extensions}
        (self.workspace / REGISTRY).write_text(json.dumps(document), encoding="utf-8")

    def text(self, rel: str) -> str:
        """Return a workspace file's text without its trailing newline."""
        return (self.workspace / rel).read_text(encoding="utf-8").rstrip("\n")

    def direct(self, *arguments: str) -> None:
        """Run the fake specify directly, the way a user bypassing the helper would."""
        executable = shutil.which("specify", path=self.env["PATH"])
        assert executable is not None
        subprocess.run([executable, *arguments], cwd=self.workspace, env=self.env, capture_output=True, check=True)  # noqa: S603 - the fake CLI

    def set_enabled(self, skill_id: str, *, enabled: bool) -> None:
        """Flip a skill's enabled flag in the registry, as specify extension enable or disable would."""
        registry = json.loads((self.workspace / REGISTRY).read_text(encoding="utf-8"))
        registry["extensions"][skill_id]["enabled"] = enabled
        (self.workspace / REGISTRY).write_text(json.dumps(registry), encoding="utf-8")


@pytest.fixture
def library(tmp_path: Path) -> Library:
    """Provide a fresh workspace with only the bootstrap installed."""
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    fake = bin_dir / "specify"
    shutil.copyfile(FIXTURES / "specify", fake)
    fake.chmod(0o755)
    workspace = tmp_path / "workspace"
    (workspace / ".specify/extensions").mkdir(parents=True)
    skipped = ("SPECKIT_CATALOG_URL", "SKILL_LIBRARY_CATALOG_URL")
    env = {key: value for key, value in os.environ.items() if key not in skipped}
    env["PATH"] = f"{bin_dir}{os.pathsep}{env.get('PATH', '')}"
    instance = Library(workspace, env)
    instance.write_registry({"skill": {"version": "1.0.0", "enabled": True}})
    return instance


def test_lists_commands_by_default(library: Library) -> None:
    assert "Commands: search" in library.ok()


def test_searches_ids_descriptions_and_facets(library: Library) -> None:
    output = library.ok("search", "architecture")

    assert re.search(r"alpha\s+1\.1\.0", output)
    assert "beta" not in output
    assert "can't find a skill matching 'nothing'" in library.ok("search", "nothing")


def test_plans_required_skills_first_and_offers_related_skills(library: Library) -> None:
    output = library.ok("plan", "alpha")

    assert re.search(r"(?s)beta\s+1\.0\.0\s+install\s+required by alpha.*alpha\s+1\.1\.0\s+install\s+requested", output)
    assert re.search(r"gamma\s+not installed\s+alpha\s+Optional extra\.", output)


def test_plans_an_exact_older_version_with_a_selected_related_skill_and_reports_conflicts(library: Library) -> None:
    library.write_registry({"beta": {"version": "0.9.0", "enabled": True}})

    output = library.ok("plan", "alpha", "-Version", "1.0.0", "-Related", "gamma")

    assert re.search(r"beta\s+1\.0\.0\s+conflict: 0\.9\.0 installed", output)
    assert re.search(r"alpha\s+1\.0\.0\s+install", output)
    assert re.search(r"gamma\s+1\.0\.0\s+install\s+related, selected", output)


def test_installs_in_dependency_order_through_specify_with_the_library_catalog(library: Library) -> None:
    library.ok("install", "alpha", "-Related", "gamma")

    assert library.log() == [
        f"extension add beta --version 1.0.0 catalog={CATALOG}",
        f"extension add alpha --version 1.1.0 catalog={CATALOG}",
        f"extension add gamma --version 1.0.0 catalog={CATALOG}",
    ]
    library.ok("install", "alpha")
    assert len(library.log()) == 3


def test_refuses_to_install_over_a_different_installed_version(library: Library) -> None:
    library.write_registry({"beta": {"version": "0.9.0", "enabled": True}})

    assert "Resolve version conflicts first: beta" in library.fails("install", "alpha")
    assert not (library.workspace / "specify.log").exists()


def test_upgrades_installed_skills_to_their_latest_versions_required_skills_first(library: Library) -> None:
    library.ok("install", "alpha", "-Version", "1.0.0")
    (library.workspace / "specify.log").unlink()

    output = library.ok("upgrade-all")

    assert re.search(r"(?s)beta\s+1\.0\.0\s+current.*alpha\s+1\.1\.0\s+upgrade from 1\.0\.0", output)
    assert library.log() == [f"extension add alpha --version 1.1.0 --force catalog={CATALOG}"]
    assert "All installed skills are at their latest versions" in library.ok("upgrade-all")


def test_reports_when_no_skills_are_installed_to_upgrade(library: Library) -> None:
    assert "No skills are installed" in library.ok("upgrade-all")


def test_records_chosen_and_required_skills_when_installing(library: Library) -> None:
    library.ok("install", "alpha", "-Version", "1.0.0", "-Related", "gamma")

    skills = library.state()["skills"]
    assert skills["alpha"]["chosen"] is True
    assert skills["gamma"]["chosen"] is True
    assert skills["beta"]["chosen"] is False
    library.ok("install", "beta")
    assert library.state()["skills"]["beta"]["chosen"] is True
    assert re.search(r"beta\s+1\.0\.0\s+True\s+chosen", library.ok("list"))


def test_upgrades_into_changed_dependencies(library: Library) -> None:
    library.ok("install", "alpha", "-Version", "1.0.0")
    (library.workspace / "specify.log").unlink()

    output = library.ok("upgrade-all", catalog=CHANGED)

    assert library.log() == [
        f"extension add delta --version 1.0.0 catalog={CHANGED}",
        f"extension add alpha --version 1.1.0 --force catalog={CHANGED}",
    ]
    assert re.search(r"epsilon\s+alpha\s+New extra\.", output)
    assert not re.search(r"gamma\s+alpha", output)
    assert "No longer required by any chosen skill: beta. Run prune to remove them." in output
    assert library.state()["skills"]["delta"]["chosen"] is False
    assert re.search(r"delta\s+1\.0\.0\s+True\s+required", library.ok("list", catalog=CHANGED))


def test_prunes_only_skills_no_chosen_skill_requires(library: Library) -> None:
    library.ok("install", "alpha", "-Version", "1.0.0")
    library.ok("upgrade-all", catalog=CHANGED)
    (library.workspace / "specify.log").unlink()

    assert "Removed 1 skill(s)." in library.ok("prune", catalog=CHANGED)

    assert library.log() == ["extension remove beta --force catalog="]
    registry = json.loads((library.workspace / REGISTRY).read_text(encoding="utf-8"))
    assert sorted(registry["extensions"]) == ["alpha", "delta", "skill"]
    assert "beta" not in library.state()["skills"]
    assert "Nothing to prune" in library.ok("prune", catalog=CHANGED)


def test_never_prunes_skills_installed_before_choices_were_recorded(library: Library) -> None:
    library.write_registry({"skill": {"version": "1.0.0", "enabled": True}, "beta": {"version": "1.0.0", "enabled": True}})

    assert "Nothing to prune" in library.ok("prune")
    assert not (library.workspace / "specify.log").exists()


def test_lists_installed_skills_and_loads_their_files_with_skill_md_first(library: Library) -> None:
    library.ok("install", "beta")

    assert re.search(r"beta\s+1\.0\.0\s+True\s+chosen", library.ok("list"))
    loaded = library.ok("load", "beta").splitlines()
    assert loaded[1] == ".specify/extensions/beta/resources/.github/skills/beta/SKILL.md"
    assert "'gamma' is not installed" in library.fails("load", "gamma")


def test_reports_an_unknown_skill(library: Library) -> None:
    assert "can't find the skill 'missing'" in library.fails("plan", "missing")


def test_copies_installed_guidance_into_github_and_records_each_copy(library: Library) -> None:
    assert "Guidance in .github/: 3 copied, 0 updated, 0 removed." in library.ok("install", "alpha")

    assert library.text(".github/skills/alpha/SKILL.md") == "# Skill alpha 1.1.0"
    assert library.text(".github/skills/beta/SKILL.md") == "# Skill beta 1.0.0"
    assert library.text(".github/instructions/shared.instructions.md") == "# Shared"
    files = library.state()["files"]
    expected = [".github/instructions/shared.instructions.md", ".github/skills/alpha/SKILL.md", ".github/skills/beta/SKILL.md"]
    assert sorted(files) == expected
    digest = hashlib.sha256((library.workspace / ".github/skills/alpha/SKILL.md").read_bytes()).hexdigest()
    assert files[".github/skills/alpha/SKILL.md"]["sha256"] == digest
    assert files[".github/skills/alpha/SKILL.md"]["version"] == "1.1.0"
    assert files[".github/instructions/shared.instructions.md"]["skill"] == "alpha"


def test_updates_unmodified_copies_on_upgrade(library: Library) -> None:
    library.ok("install", "alpha", "-Version", "1.0.0")

    assert "Guidance in .github/: 0 copied, 1 updated, 0 removed." in library.ok("upgrade-all")

    assert library.text(".github/skills/alpha/SKILL.md") == "# Skill alpha 1.1.0"
    assert library.state()["files"][".github/skills/alpha/SKILL.md"]["version"] == "1.1.0"


def test_keeps_a_modified_copy_on_upgrade_and_reports_it(library: Library) -> None:
    library.ok("install", "alpha", "-Version", "1.0.0")
    (library.workspace / ".github/skills/alpha/SKILL.md").write_text("# Local edit\n", encoding="utf-8")

    output = library.ok("upgrade-all")

    copied = r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z"
    pattern = rf"Kept \.github/skills/alpha/SKILL\.md: modified since alpha 1\.0\.0 copied it on {copied}; alpha 1\.1\.0 was not applied\."
    assert re.search(pattern, output)
    assert library.text(".github/skills/alpha/SKILL.md") == "# Local edit"
    assert library.state()["files"][".github/skills/alpha/SKILL.md"]["version"] == "1.0.0"


def test_removes_a_skill_with_its_unmodified_copies_and_keeps_modified_ones(library: Library) -> None:
    library.ok("install", "gamma")
    library.ok("install", "beta")

    assert "Guidance in .github/: 0 copied, 0 updated, 1 removed." in library.ok("remove", "beta")
    assert not (library.workspace / ".github/skills/beta").exists()
    assert (library.workspace / ".github/instructions/shared.instructions.md").exists()

    (library.workspace / ".github/skills/gamma/SKILL.md").write_text("# Local edit\n", encoding="utf-8")
    output = library.ok("remove", "gamma")

    assert re.search(
        r"Kept \.github/skills/gamma/SKILL\.md: modified since gamma 1\.0\.0 copied it on .*\. Review it before deleting it\.", output
    )
    assert "1 removed." in output
    assert library.text(".github/skills/gamma/SKILL.md") == "# Local edit"
    assert not (library.workspace / ".github/instructions").exists()
    assert library.state()["files"] == {}
    assert library.log()[-2:] == ["extension remove beta --force catalog=", "extension remove gamma --force catalog="]


def test_refuses_to_remove_a_skill_another_installed_skill_requires(library: Library) -> None:
    library.ok("install", "alpha")

    assert "'beta' is required by alpha" in library.fails("remove", "beta")
    assert "extension remove beta --force catalog=" not in library.log()
    assert "specify extension remove skill" in library.fails("remove", "skill")


def test_never_overwrites_or_deletes_a_file_it_did_not_copy(library: Library) -> None:
    mine = library.workspace / ".github/skills/beta/SKILL.md"
    mine.parent.mkdir(parents=True)
    mine.write_text("# Mine\n", encoding="utf-8")

    expected = "Kept .github/skills/beta/SKILL.md: it exists and was not copied by the skill library."
    assert expected in library.ok("install", "beta")
    assert ".github/skills/beta/SKILL.md" not in library.state()["files"]
    library.ok("remove", "beta")
    assert library.text(".github/skills/beta/SKILL.md") == "# Mine"


def test_restores_missing_copies_on_sync(library: Library) -> None:
    library.ok("install", "beta")
    (library.workspace / ".github/skills/beta/SKILL.md").unlink()

    assert "Guidance in .github/: 1 copied, 0 updated, 0 removed." in library.ok("sync")
    assert library.text(".github/skills/beta/SKILL.md") == "# Skill beta 1.0.0"


def test_records_the_version_and_enabled_flag_of_every_installed_skill(library: Library) -> None:
    assert "Warning:" not in library.ok("install", "alpha", "-Version", "1.0.0")

    state = library.state()
    raw = json.loads((library.workspace / ".specify/extensions/.skill-library.json").read_text(encoding="utf-8"))
    assert raw["schema_version"] == "1.2"
    assert state["skills"]["alpha"]["version"] == "1.0.0"
    assert state["skills"]["alpha"]["enabled"] is True
    assert state["skills"]["beta"]["version"] == "1.0.0"
    assert "Warning:" not in library.ok("upgrade-all")
    assert library.state()["skills"]["alpha"]["version"] == "1.1.0"


def test_warns_about_a_skill_removed_outside_the_skill_library_until_sync_deletes_its_guidance(library: Library) -> None:
    library.ok("install", "gamma")
    library.direct("extension", "remove", "gamma", "--force")

    output = library.ok("list")

    expected = (
        "Warning: gamma was removed outside the skill library. "
        "Run install gamma to restore it, or sync to delete its guidance from .github/."
    )
    assert expected in output
    assert MANAGE_HINT in output
    assert "Warning:" not in library.ok("help")
    assert "Guidance in .github/: 0 copied, 0 updated, 2 removed." in library.ok("sync")
    assert not (library.workspace / ".github/skills/gamma").exists()
    assert "Warning:" not in library.ok("list")


def test_warns_about_skills_installed_or_upgraded_outside_the_skill_library_until_sync_copies_their_guidance(library: Library) -> None:
    library.ok("install", "alpha", "-Version", "1.0.0")
    library.direct("extension", "add", "gamma", "--version", "1.0.0")
    library.direct("extension", "add", "alpha", "--version", "1.1.0", "--force")

    output = library.ok("list")

    assert "Warning: alpha changed from 1.0.0 to 1.1.0 outside the skill library. Run sync to update its guidance in .github/." in output
    assert "Warning: gamma 1.0.0 was installed outside the skill library. Run sync to copy its guidance into .github/." in output
    assert MANAGE_HINT in output
    assert "Guidance in .github/: 1 copied, 1 updated, 0 removed." in library.ok("sync")
    assert library.text(".github/skills/alpha/SKILL.md") == "# Skill alpha 1.1.0"
    assert library.text(".github/skills/gamma/SKILL.md") == "# Skill gamma 1.0.0"
    output = library.ok("list")
    assert "Warning:" not in output
    assert re.search(r"gamma\s+1\.0\.0\s+True\s+chosen", output)


def test_warns_about_a_skill_disabled_or_enabled_outside_the_skill_library_until_sync_applies_it(library: Library) -> None:
    library.ok("install", "beta")
    library.set_enabled("beta", enabled=False)

    assert "Warning: beta was disabled outside the skill library. Run sync to delete its guidance from .github/." in library.ok("list")
    assert "Guidance in .github/: 0 copied, 0 updated, 2 removed." in library.ok("sync")
    assert "Warning:" not in library.ok("list")
    library.set_enabled("beta", enabled=True)
    assert "Warning: beta was enabled outside the skill library. Run sync to copy its guidance into .github/." in library.ok("list")
    assert "Guidance in .github/: 2 copied, 0 updated, 0 removed." in library.ok("sync")
    assert "Warning:" not in library.ok("list")


def test_does_not_treat_skills_missing_from_an_older_state_file_as_installed_outside(library: Library) -> None:
    state = library.workspace / ".specify/extensions/.skill-library.json"
    state.write_text('{"schema_version":"1.1","skills":{},"files":{}}', encoding="utf-8")
    library.direct("extension", "add", "beta", "--version", "1.0.0")

    assert "Warning:" not in library.ok("list")
    library.ok("sync")
    assert library.state()["skills"]["beta"]["chosen"] is True
    assert "Warning:" not in library.ok("list")


def test_reads_the_packaged_catalog_url_and_fails_only_catalog_commands_without_one(library: Library, tmp_path: Path) -> None:
    extension = tmp_path / "extension"
    (extension / "scripts/python").mkdir(parents=True)
    copy = extension / "scripts/python/skill_library.py"
    shutil.copyfile(SCRIPT, copy)

    def run(*arguments: str) -> subprocess.CompletedProcess[str]:
        command = [sys.executable, str(copy), *arguments, "-Workspace", str(library.workspace)]
        return subprocess.run(command, capture_output=True, text=True, env=library.env, check=False)  # noqa: S603 - the helper copy

    assert "Commands: search" in run("help").stdout
    missing = run("search", "architecture")
    assert missing.returncode == 1
    assert "No skill library catalog is configured; set SKILL_LIBRARY_CATALOG_URL or reinstall the skill extension." in missing.stderr
    (extension / "skill-library.json").write_text(json.dumps({"catalog_url": str(CATALOG)}), encoding="utf-8")
    assert re.search(r"alpha\s+1\.1\.0", run("search", "architecture").stdout)
