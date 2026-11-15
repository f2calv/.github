"""Exercise source-link handling using only synthetic staged documentation."""

from __future__ import annotations

import importlib.util
from pathlib import Path

from markdown import Markdown
from mkdocs.structure.files import File, Files
import pytest

SPEC = importlib.util.spec_from_file_location("mkdocs_hooks", Path(__file__).parents[1] / "mkdocs_hooks.py")
assert SPEC is not None and SPEC.loader is not None
HOOKS = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(HOOKS)


def render_links(tmp_path: Path, text: str) -> str:
    processor = HOOKS.RepositoryLinks(None, tmp_path, "https://github.com/owner/example", {".scripts/helper.ps1"})
    processor.source = "docs/guide.md"
    return Markdown(extensions=[HOOKS.RepositoryLinkExtension(processor)]).convert(text)


def test_keeps_staged_document_links_local(tmp_path: Path) -> None:
    (tmp_path / "README.md").write_text("# Home", encoding="utf-8")
    assert 'href="../README.md#home"' in render_links(tmp_path, "[Home](../README.md#home)")


def test_routes_tracked_non_documents_to_public_source(tmp_path: Path) -> None:
    assert 'href="https://github.com/owner/example/blob/main/.scripts/helper.ps1#example"' in render_links(
        tmp_path, "[Script](../.scripts/helper.ps1#example)",
    )


def test_leaves_missing_targets_for_strict_validation(tmp_path: Path) -> None:
    assert 'href="../missing.md"' in render_links(tmp_path, "[Missing](../missing.md)")


def test_never_rewrites_code_samples(tmp_path: Path) -> None:
    assert "https://github.com/owner/example/blob" not in render_links(tmp_path, "`[Script](../.scripts/helper.ps1)`")


def test_routes_tracked_directory_links_to_source(tmp_path: Path) -> None:
    assert 'href="https://github.com/owner/example/tree/main/.scripts"' in render_links(tmp_path, "[Scripts](../.scripts/)")


def test_preserves_github_heading_anchors() -> None:
    assert HOOKS.github_slug("Step 6 \u2014 Strip Agent Attribution", "-") == "step-6--strip-agent-attribution"


def test_publishes_guidance_without_changing_canonical_source_paths(tmp_path: Path) -> None:
    file = File(".github/guide.md", str(tmp_path), str(tmp_path / "site"), True)
    HOOKS.on_files(Files([file]))
    assert file.src_uri == ".github/guide.md"
    assert file.dest_uri == "guidance/guide/index.html"
    assert file.url == "guidance/guide/"


def test_rejects_guidance_output_collisions(tmp_path: Path) -> None:
    files = Files([
        File(".github/guide.md", str(tmp_path), str(tmp_path / "site"), True),
        File("guidance/guide.md", str(tmp_path), str(tmp_path / "site"), True),
    ])
    with pytest.raises(ValueError, match="collides"):
        HOOKS.on_files(files)
