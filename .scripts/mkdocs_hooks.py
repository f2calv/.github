"""Adapt canonical repository links for the staged public documentation site."""

from __future__ import annotations

import posixpath
import re
import subprocess
from pathlib import Path
from typing import TYPE_CHECKING
from urllib.parse import quote, unquote, urlsplit, urlunsplit

from markdown.extensions import Extension
from markdown.treeprocessors import Treeprocessor

if TYPE_CHECKING:
    from xml.etree.ElementTree import Element

    from markdown import Markdown
    from mkdocs.config.defaults import MkDocsConfig
    from mkdocs.structure.files import Files
    from mkdocs.structure.pages import Page


class RepositoryLinks(Treeprocessor):
    """Resolve non-document repository links without modifying code examples."""

    def __init__(self, md: Markdown, root: Path, repository_url: str, tracked: set[str]) -> None:
        """Capture the public source boundary and current document path."""
        super().__init__(md)
        self.root = root
        self.repository_url = repository_url
        self.tracked = tracked
        self.source = "README.md"

    def run(self, root: Element) -> Element:
        """Keep built documents local and route other tracked sources to GitHub."""
        for element in root.iter():
            attribute = {"a": "href", "img": "src"}.get(element.tag)
            if attribute is None or attribute not in element.attrib:
                continue
            value = element.attrib[attribute]
            url = urlsplit(value)
            if url.scheme or url.netloc or not url.path or url.path.startswith("/"):
                continue
            target = posixpath.normpath(posixpath.join(posixpath.dirname(self.source), unquote(url.path)))
            if (self.root / target).is_file():
                continue
            directory = target not in self.tracked and any(path.startswith(f"{target}/") for path in self.tracked)
            if target not in self.tracked and not directory:
                continue
            kind = "tree" if directory else "blob"
            path = f"{self.repository_url}/{kind}/main/{quote(target, safe='/')}"
            element.attrib[attribute] = urlunsplit((*urlsplit(path)[:3], url.query, url.fragment))
        return root


class RepositoryLinkExtension(Extension):
    """Run repository link resolution before MkDocs validates link targets."""

    def __init__(self, processor: RepositoryLinks) -> None:
        """Share the processor with the page event handler."""
        super().__init__()
        self.processor = processor

    def extendMarkdown(self, md: Markdown) -> None:  # noqa: N802
        """Register the Markdown extension API entry point."""
        self.processor.md = md
        md.treeprocessors.register(self.processor, "repository_links", 15)


_processor: RepositoryLinks | None = None


def github_slug(value: str, separator: str) -> str:
    """Preserve GitHub's consecutive hyphens in canonical heading anchors."""
    return re.sub(r"\s", separator, re.sub(r"[^\w\-\s]", "", value.lower()))


def on_config(config: MkDocsConfig) -> MkDocsConfig:
    """Enumerate tracked targets without consulting ignored workstation files."""
    global _processor  # noqa: PLW0603
    root = Path(config.docs_dir)
    result = subprocess.run(
        ["git", "-C", str(root.parent), "-c", "core.quotePath=false", "ls-files"],
        check=True,
        capture_output=True,
        text=True,
    )
    _processor = RepositoryLinks(None, root, str(config.repo_url).rstrip("/"), set(result.stdout.splitlines()))
    config.markdown_extensions.append(RepositoryLinkExtension(_processor))
    config.mdx_configs.setdefault("toc", {})["slugify"] = github_slug
    return config


def on_page_markdown(markdown: str, page: Page, **kwargs: object) -> str:
    """Set the canonical page path before the Markdown link processor runs."""
    if _processor is None:
        msg = "Documentation link processor was not configured."
        raise RuntimeError(msg)
    _processor.source = page.file.src_uri
    return markdown


def on_files(files: Files, **kwargs: object) -> Files:
    """Publish canonical .github sources beneath a Pages-compatible output path."""
    destinations = {file.dest_uri for file in files if not file.src_uri.startswith(".github/")}
    for file in files:
        if not file.src_uri.startswith(".github/"):
            continue
        destination = "guidance/" + file.dest_uri.removeprefix(".github/")
        if destination in destinations:
            msg = "Generated guidance collides with another page; choose distinct publication paths."
            raise ValueError(msg)
        destinations.add(destination)
        file.dest_uri = destination
    return files
