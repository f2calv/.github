"""Read restricted YAML metadata or native frontmatter as JSON without coercion."""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path
from typing import TypeAlias

import yaml
from yaml.nodes import MappingNode, Node, ScalarNode, SequenceNode
from yaml.tokens import AliasToken, AnchorToken, TagToken

JsonValue: TypeAlias = None | bool | int | float | str | list["JsonValue"] | dict[str, "JsonValue"]
ALLOWED_TAGS = {f"tag:yaml.org,2002:{name}" for name in ("map", "seq", "str", "int", "float", "bool", "null")}


def _convert(node: Node, loader: yaml.SafeLoader, depth: int = 0) -> JsonValue:
    if depth > 40 or node.tag not in ALLOWED_TAGS:
        raise ValueError("Use JSON-compatible YAML types with at most 40 nesting levels.")
    if isinstance(node, MappingNode):
        result: dict[str, JsonValue] = {}
        for key, value in node.value:
            if not isinstance(key, ScalarNode) or key.tag != "tag:yaml.org,2002:str":
                raise ValueError("Use string mapping keys; merges and complex keys are not supported.")
            if key.value in result:
                raise ValueError("Remove duplicate YAML mapping keys.")
            result[key.value] = _convert(value, loader, depth + 1)
        return result
    if isinstance(node, SequenceNode):
        return [_convert(value, loader, depth + 1) for value in node.value]
    if isinstance(node, ScalarNode):
        scalar = loader.construct_object(node)
        if isinstance(scalar, float) and not math.isfinite(scalar):
            raise ValueError("Use finite JSON numbers.")
        if scalar is None or isinstance(scalar, (str, bool, int, float)):
            return scalar
    raise ValueError("Use JSON-compatible YAML nodes.")


def _read(path: Path, frontmatter: bool) -> JsonValue:
    if path.stat().st_size > 1_048_576:
        raise ValueError("Keep metadata inputs below 1 MiB.")
    text = path.read_text(encoding="utf-8")
    if frontmatter:
        lines = text.splitlines()
        if not lines or lines[0] != "---" or "---" not in lines[1:]:
            raise ValueError("Provide delimited native YAML frontmatter.")
        text = "\n".join(lines[1:lines.index("---", 1)])
    if any(isinstance(token, (AliasToken, AnchorToken, TagToken)) for token in yaml.scan(text)):
        raise ValueError("Remove YAML aliases, anchors and explicit tags.")
    loader = yaml.SafeLoader(text)
    try:
        node = loader.get_single_node()
        if node is None:
            raise ValueError("Provide one nonempty YAML document.")
        return _convert(node, loader)
    finally:
        loader.dispose()


def main() -> int:
    """Return JSON on success and sanitized diagnostics on failure."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("path", type=Path)
    parser.add_argument("--frontmatter", action="store_true")
    arguments = parser.parse_args()
    try:
        if sys.version_info < (3, 11) or yaml.__version__ != "6.0.3":
            raise ValueError("Use Python 3.11+ with PyYAML 6.0.3.")
        value = _read(arguments.path, arguments.frontmatter)
        sys.stdout.write(json.dumps(value, allow_nan=False, ensure_ascii=True) + "\n")
    except UnicodeError:
        sys.stderr.write("Metadata parsing failed: use UTF-8 input.\n")
        return 1
    except ValueError as error:
        sys.stderr.write(f"Metadata parsing failed: {error}\n")
        return 1
    except (OSError, yaml.YAMLError, RecursionError):
        sys.stderr.write("Metadata parsing failed: check readable UTF-8, single-document YAML and nesting.\n")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
