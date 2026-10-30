"""Dispatch the shared library command without consulting a source checkout."""

from __future__ import annotations

import argparse
import importlib.util
import json
import re
import shutil
import stat
import subprocess
import sys
import zipfile
from dataclasses import dataclass
from pathlib import Path
from typing import TYPE_CHECKING, Any

if TYPE_CHECKING:
    from collections.abc import Sequence
    from types import ModuleType


class LibraryError(ValueError):
    """Report a safe library-command failure at the process boundary."""

    def __init__(self, message: str, exit_code: int = 2) -> None:
        super().__init__(message)
        self.exit_code = exit_code


@dataclass(frozen=True, slots=True)
class LibraryRequest:
    """Retain the parsed operation independently of release resolution."""

    action: str
    identity: str = ""
    version: str | None = None
    query: tuple[str, ...] = ()
    optional: tuple[str, ...] = ()
    apply: bool = False
    reviewed_fingerprint: str | None = None


class LibraryParser(argparse.ArgumentParser):
    """Reject invalid arguments without printing caller-controlled contents."""

    def error(self, message: str) -> None:
        raise LibraryError("Arguments: Use search, install, list --installed, or load; check the selected options.")


def parse_arguments(arguments: Sequence[str]) -> LibraryRequest:
    """Parse command aliases and mutually exclusive release selectors."""
    if not arguments or list(arguments) in (["help"], ["--help"], ["-h"]):
        return LibraryRequest("Help")
    operation, *tail = arguments
    if operation not in {"search", "install", "list", "load"}:
        if any(value.startswith("-") for value in arguments):
            raise LibraryError("Arguments: Unknown option.")
        return LibraryRequest("Discover", query=tuple(arguments))
    parser = LibraryParser(add_help=False, allow_abbrev=False)
    if operation == "search":
        parser.add_argument("query", nargs="*")
        return LibraryRequest("Search", query=tuple(parser.parse_args(tail).query))
    if operation == "list":
        parser.add_argument("--installed", action="store_true", required=True)
        parser.parse_args(tail)
        return LibraryRequest("Installed")
    parser.add_argument("identity")
    if operation == "install":
        releases = parser.add_mutually_exclusive_group()
        releases.add_argument("--latest", action="store_true")
        releases.add_argument("--version")
        parser.add_argument("--optional", action="append", default=[])
        parser.add_argument("--apply", action="store_true")
        parser.add_argument("--reviewed-fingerprint")
    else:
        parser.add_argument("query", nargs=argparse.REMAINDER)
    parsed = parser.parse_args(tail)
    if re.fullmatch(r"[a-z0-9]+(?:-[a-z0-9]+)*", parsed.identity) is None:
        raise LibraryError("Arguments: Select an exact lowercase skill ID.")
    if operation == "load":
        return LibraryRequest("Load", identity=parsed.identity, query=tuple(parsed.query))
    if parsed.version is not None and re.fullmatch(r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)", parsed.version) is None:
        raise LibraryError("Arguments: An exact X.Y.Z version is required.")
    if len(set(parsed.optional)) != len(parsed.optional):
        raise LibraryError("Arguments: Optional selections must be unique.")
    if parsed.apply and (parsed.version is None or parsed.reviewed_fingerprint is None or re.fullmatch(r"[a-f0-9]{64}", parsed.reviewed_fingerprint) is None):
        raise LibraryError("Arguments: Apply requires the exact preview version and lowercase reviewed fingerprint.")
    if parsed.reviewed_fingerprint is not None and not parsed.apply:
        raise LibraryError("Arguments: A reviewed fingerprint is accepted only with apply.")
    return LibraryRequest("Install", identity=parsed.identity, version=parsed.version, optional=tuple(parsed.optional), apply=parsed.apply, reviewed_fingerprint=parsed.reviewed_fingerprint)


def _bridge() -> ModuleType:
    name = "skill_library_install_bridge"
    if name not in sys.modules:
        specification = importlib.util.spec_from_file_location(name, Path(__file__).with_name("Invoke-SpecKitInstall.py"))
        if specification is None or specification.loader is None:
            raise LibraryError("Prerequisite: The bundled installation verifier is missing.")
        module = importlib.util.module_from_spec(specification)
        sys.modules[name] = module
        specification.loader.exec_module(module)
    return sys.modules[name]


def _catalog(path: Path) -> dict[str, Any]:
    bridge = _bridge()
    catalog = bridge._read_json(bridge._bytes(bridge._safe_path(str(path))).decode("utf-8"))
    if not isinstance(catalog, dict) or set(catalog) != {"schema_version", "skills"} or catalog["schema_version"] != "skill-library/1":
        raise LibraryError("Catalog: Use a valid bundled library release index.")
    if not isinstance(catalog["skills"], dict) or len(catalog["skills"]) > 1000:
        raise LibraryError("Catalog: Invalid skill collection.")
    for identity, record in catalog["skills"].items():
        if re.fullmatch(r"[a-z0-9]+(?:-[a-z0-9]+)*", identity) is None or not isinstance(record, dict) or set(record) != {"current", "releases"}:
            raise LibraryError("Catalog: Invalid skill identity.")
        if not isinstance(record["releases"], dict) or not record["releases"] or len(record["releases"]) > 100 or record["current"] not in record["releases"]:
            raise LibraryError("Catalog: The advertised current release is unavailable.")
        for version, release in record["releases"].items():
            if re.fullmatch(r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)", version) is None:
                raise LibraryError("Catalog: Invalid release version.")
            if not isinstance(release, dict) or set(release) != {"archive", "catalog"} or release["archive"] != f"{identity}-{version}.zip":
                raise LibraryError("Catalog: Invalid artifact location.")
            if not isinstance(release["catalog"], dict) or release["catalog"].get("version") != version:
                raise LibraryError("Catalog: Inconsistent release identity.")
    return catalog


def _release(catalog: dict[str, Any], artifacts: Path, identity: str, version: str | None = None) -> dict[str, Any]:
    if identity not in catalog["skills"]:
        raise LibraryError("NotFound: Sorry, we can't find that skill.")
    skill = catalog["skills"][identity]
    selected_version = version if version is not None else skill["current"]
    if selected_version not in skill["releases"]:
        raise LibraryError("VersionUnavailable: Select an available exact release.")
    release = skill["releases"][selected_version]
    bridge = _bridge()
    archive_path = bridge._safe_path(str(artifacts / release["archive"]))
    if bridge._digest(bridge._bytes(archive_path, bridge.MAX_ARCHIVE)) != release["catalog"].get("sha256"):
        raise LibraryError("Artifact: Release archive digest mismatch.")
    with archive_path.open("rb") as stream:
        with zipfile.ZipFile(stream) as archive:
            entry = archive.getinfo("source-manifest.json")
            if entry.file_size > bridge.MAX_MEMBER or entry.compress_type != zipfile.ZIP_STORED:
                raise LibraryError("Artifact: Invalid source evidence.")
            manifest = bridge._read_json(archive.read(entry).decode("utf-8"))
        if manifest["Root"]["Id"] != identity or manifest["Root"]["Version"] != selected_version:
            raise LibraryError("Artifact: Release identity mismatch.")
        selection = {"Root": manifest["Root"], "SourceCommit": manifest["SourceCommit"], "Inventory": {"Components": manifest["Components"]}, "Payload": manifest["Payload"]}
        verified = bridge._verify_artifact({"Selection": selection, "Catalog": release["catalog"], "ArchivePath": str(archive_path)}, stream)
        component_metadata = {}
        with zipfile.ZipFile(stream) as archive:
            if not isinstance(manifest["Components"], list) or not 1 <= len(manifest["Components"]) <= 1000:
                raise LibraryError("Artifact: Invalid required component collection.")
            for component in manifest["Components"]:
                record = bridge._read_yaml(archive.read(f"resources/library/{component['NativeFolder']}/skill.metadata.yaml").decode("utf-8"))
                if not isinstance(record, dict) or record.get("id") != component["Id"] or record.get("version") != component["Version"] or component["Id"] in component_metadata:
                    raise LibraryError("Artifact: Inconsistent required component metadata.")
                component_metadata[component["Id"]] = {"Id": component["Id"], "NativeFolder": component["NativeFolder"], "Metadata": record}
            prefix = f"resources/library/{manifest['Root']['Folder']}/"
            native = archive.read(prefix + "SKILL.md").decode("utf-8").splitlines()
            if not native or native[0] != "---" or "---" not in native[1:]:
                raise LibraryError("Artifact: Missing canonical discovery metadata.")
            end = native.index("---", 1)
            frontmatter = bridge._read_yaml("\n".join(native[1:end]))
            metadata = bridge._read_yaml(archive.read(prefix + "skill.metadata.yaml").decode("utf-8"))
    if metadata.get("id") != identity or metadata.get("version") != selected_version:
        raise LibraryError("Artifact: Inconsistent canonical metadata.")
    facets = metadata.get("facets", [])
    if not isinstance(facets, list) or not all(isinstance(value, str) for value in facets):
        raise LibraryError("Artifact: Invalid canonical facets.")
    if not isinstance(frontmatter.get("name"), str) or not isinstance(frontmatter.get("description"), str):
        raise LibraryError("Artifact: Invalid native discovery metadata.")
    return {
        "Id": identity, "Version": selected_version, "Name": frontmatter["name"],
        "Description": frontmatter["description"], "Facets": facets,
        "Sha256": verified["Archive"]["Sha256"], "SourceCommit": manifest["SourceCommit"],
        "Required": [{"Id": item["Id"], "Version": item["Version"]} for item in manifest["Components"]],
        "Optional": metadata.get("optional", []), "Manifest": manifest,
        "_Verified": verified, "_Metadata": component_metadata,
    }


def _summary(release: dict[str, Any]) -> dict[str, Any]:
    return {key: value for key, value in release.items() if key != "Manifest" and not key.startswith("_")}


def _selected_releases(request: LibraryRequest, catalog: dict[str, Any], artifacts: Path) -> list[dict[str, Any]]:
    root = _release(catalog, artifacts, request.identity, request.version)
    selected = {root["Id"]: root}
    edges: dict[str, set[str]] = {}
    pending = list(request.optional)
    while pending:
        progressed = False
        for key in list(pending):
            active = {identity: record for release in selected.values() for identity, record in release["_Metadata"].items()}
            offers = [offer for identity, record in active.items() for offer in record["Metadata"].get("optional", []) if f"{identity}/{offer['selectionKey']}" == key]
            if len(offers) != 1:
                continue
            offer = offers[0]
            peer = _release(catalog, artifacts, offer["id"], offer["version"])
            if peer["Id"] in selected and selected[peer["Id"]]["Version"] != peer["Version"]:
                raise LibraryError("Selection: Conflicting exact optional versions.")
            selected[peer["Id"]] = peer
            edges.setdefault(key.split("/", 1)[0], set()).add(peer["Id"])
            edges.setdefault(peer["Id"], set())
            if len(selected) > 16:
                raise LibraryError("Selection: At most sixteen extension roots may be selected.")
            pending.remove(key)
            progressed = True
        if not progressed:
            raise LibraryError("Selection: An optional key is unknown or its declaring skill is inactive.")
    active = {identity: record for release in selected.values() for identity, record in release["_Metadata"].items()}
    for identity, record in active.items():
        edges.setdefault(identity, set()).update(edge["id"] for edge in record["Metadata"].get("required", []))
    if any(dependency not in active for dependencies in edges.values() for dependency in dependencies):
        raise LibraryError("Selection: A selected package omits required component metadata.")
    remaining = edges
    while remaining:
        leaves = {identity for identity, dependencies in remaining.items() if not dependencies}
        if not leaves:
            raise LibraryError("Selection: The selected dependency graph contains a cycle.")
        remaining = {identity: dependencies - leaves for identity, dependencies in remaining.items() if identity not in leaves}
    return [root, *[selected[key] for key in sorted(selected) if key != root["Id"]]]


def _package_selection(request: LibraryRequest, catalog_path: Path, artifacts: Path) -> dict[str, Any]:
    if request.action != "Install" or request.apply:
        raise LibraryError("Arguments: Packaged selection requires an install request.")
    bridge = _bridge()
    catalog_path = bridge._safe_path(str(catalog_path))
    index_bytes = bridge._bytes(catalog_path)
    catalog = _catalog(catalog_path)
    releases = _selected_releases(request, catalog, artifacts)
    tools = [{"Role": "release-index", "Path": str(catalog_path), "Sha256": bridge._digest(index_bytes)}]
    for path in (Path(__file__).resolve(), Path(bridge.__file__).resolve(), Path(__file__).resolve().with_name("Read-Metadata.py"), Path(__file__).resolve().with_name("Invoke-Validation.ps1"), Path(__file__).resolve().parent.parent / "skill-metadata.schema.json"):
        tools.append({"Role": "package-tool", "Path": str(path), "Sha256": bridge._digest(bridge._bytes(bridge._safe_path(str(path)), bridge.MAX_ARCHIVE))})
    roots = []
    inventories = []
    release_artifacts = []
    components: dict[str, Any] = {}
    metadata_records: dict[str, Any] = {}
    for position, release in enumerate(releases):
        manifest = release["Manifest"]
        roots.append({**manifest["Root"], "SourceCommit": manifest["SourceCommit"]})
        inventories.append({"Position": position, "SourceCommit": manifest["SourceCommit"], "Inventory": {"Components": manifest["Components"]}, "Payload": manifest["Payload"]})
        for component in manifest["Components"]:
            if component["Id"] in components and components[component["Id"]]["Version"] != component["Version"]:
                raise LibraryError("Selection: Conflicting exact required versions.")
            components[component["Id"]] = component
        for identity, record in release["_Metadata"].items():
            if identity in metadata_records and metadata_records[identity] != record:
                raise LibraryError("Selection: Conflicting metadata for the same required component version.")
            metadata_records[identity] = record
        archive = release["_Verified"]["Archive"]
        path = bridge._safe_path(archive["Path"])
        if bridge._digest(bridge._bytes(path, bridge.MAX_ARCHIVE)) != archive["Sha256"]:
            raise LibraryError("Artifact: Selected release changed during inspection.")
        release_artifacts.append({"RootId": release["Id"], "Version": release["Version"], "Path": str(path), "Sha256": archive["Sha256"]})
    if bridge._bytes(catalog_path) != index_bytes:
        raise LibraryError("Catalog: Release index changed during inspection.")
    root = releases[0]["Manifest"]
    offers = []
    for identity, record in sorted(metadata_records.items()):
        for index, offer in enumerate(record["Metadata"].get("optional", [])):
            key = f"{identity}/{offer['selectionKey']}"
            offers.append({"DeclaringId": identity, "SelectionKey": offer["selectionKey"], "Selection": key, "TargetId": offer["id"], "Version": offer["version"], "Reason": offer["reason"], "SourcePath": record["NativeFolder"] + "/skill.metadata.yaml", "OptionalIndex": index, "Selected": key in request.optional})
    available = {identity: list(record["releases"]) for identity, record in catalog["skills"].items()}
    for identity, record in metadata_records.items():
        available[identity] = sorted(set([*available.get(identity, []), record["Metadata"]["version"]]))
    return {
        "SourceKind": "packaged", "SourceRoot": str(catalog_path.parent), "SourceCommit": root["SourceCommit"],
        "Root": root["Root"], "OptionalSelection": sorted(request.optional),
        "ActiveComponents": list(components.values()), "ExtensionRoots": roots,
        "RequiredInventories": inventories, "Inventory": {"Components": root["Components"]},
        "Payload": root["Payload"], "OptionalOffers": offers, "Tools": tools, "Artifacts": release_artifacts,
        "ComponentMetadata": list(metadata_records.values()), "AvailableVersions": available,
    }


def _installed(workspace: Path) -> dict[str, Any]:
    bridge = _bridge()
    root = bridge._safe_path(str(workspace))
    options = bridge._read_json(bridge._bytes(root / ".specify/init-options.json").decode("utf-8"))
    if not isinstance(options, dict) or options.get("ai") != "copilot" or options.get("ai_skills") is not True:
        raise LibraryError("Workspace: Initialize a compatible Copilot skills-mode consumer first.")
    registry_path = bridge._safe_path(str(root / ".specify/extensions/.registry"), missing=True)
    if not registry_path.exists():
        return {}
    registry = bridge._read_json(bridge._bytes(registry_path).decode("utf-8"))
    if not isinstance(registry, dict) or set(registry) != {"schema_version", "extensions"} or registry["schema_version"] != "1.0" or not isinstance(registry["extensions"], dict):
        raise LibraryError("Workspace: Inspect the invalid extension registry before continuing.")
    for identity, record in registry["extensions"].items():
        if re.fullmatch(r"[a-z0-9]+(?:-[a-z0-9]+)*", identity) is None or not isinstance(record, dict) or not isinstance(record.get("version"), str) or type(record.get("enabled")) is not bool:
            raise LibraryError("Workspace: Inspect the invalid extension registration before continuing.")
    return registry["extensions"]


def _workspace_operation(request: LibraryRequest, catalog: dict[str, Any], catalog_path: Path, artifacts: Path, workspace: Path) -> dict[str, Any]:
    releases = _selected_releases(request, catalog, artifacts)
    executable = shutil.which("pwsh")
    if executable is None:
        raise LibraryError("Prerequisite: An existing PowerShell 7.4+ installation is required; nothing was installed.")
    bridge = _bridge()
    script = bridge._safe_path(str(Path(__file__).resolve().with_name("Invoke-WorkspaceInstall.ps1")))
    arguments = {
        "PackageIndexPath": str(catalog_path), "PackageVersion": releases[0]["Version"],
        "SkillName": request.identity, "WorkspacePath": str(workspace),
        "ArtifactDirectory": [str(artifacts)], "PythonPath": sys.executable,
        "OptionalSelection": list(request.optional), "Apply": request.apply,
    }
    if request.apply:
        arguments["ReviewedFingerprint"] = request.reviewed_fingerprint
    completed = subprocess.run([executable, "-NoLogo", "-NoProfile", "-File", str(script), "-LibraryRequest", "-Json"], input=json.dumps(arguments), capture_output=True, text=True, check=False)
    if completed.returncode not in (0, 2, 3) or completed.stderr or len(completed.stdout.encode("utf-8")) > bridge.MAX_STATE:
        raise LibraryError("Workspace: No verified operation response; preserve and inspect operation evidence before retrying.", 3 if request.apply else 2)
    try:
        result = bridge._read_json(completed.stdout)
    except (ValueError, TypeError) as error:
        raise LibraryError("Workspace: An unreadable operation response requires evidence inspection before retrying.", 3 if request.apply else 2) from error
    expected_mode = "apply" if request.apply else "preview"
    if not isinstance(result, dict) or result.get("Contract") != bridge.CONTRACT or result.get("Mode") != expected_mode:
        raise LibraryError("Workspace: The operation response did not match the approved protocol.", 3 if request.apply else 2)
    if request.apply:
        return {"Action": "Apply", "Result": result}
    return {"Action": "Preview", "RequiresApproval": result.get("Ready") is True, "Preview": result}


def _load(request: LibraryRequest, workspace: Path, catalog: dict[str, Any], artifacts: Path) -> dict[str, Any]:
    installed = _installed(workspace)
    if request.identity not in installed or installed[request.identity]["enabled"] is not True:
        raise LibraryError("NotInstalled: Install and enable this exact skill before loading it.")
    registration = installed[request.identity]
    release = _release(catalog, artifacts, request.identity, registration["version"])
    bridge = _bridge()
    root = workspace / ".specify/extensions" / request.identity
    generated_manifest = next(item for item in release["_Verified"]["Members"] if item["MemberPath"] == "extension.yml")
    if registration.get("manifest_hash") != f"sha256:{generated_manifest['Sha256']}":
        raise LibraryError("Workspace: The registered manifest does not match the selected release.")
    for member in release["_Verified"]["Members"]:
        path = bridge._safe_path(str(root / member["MemberPath"]))
        data = bridge._bytes(path, bridge.MAX_MEMBER)
        if len(data) != member["Size"] or bridge._digest(data) != member["Sha256"] or stat.S_IMODE(path.stat().st_mode) != int(member["Mode"], 8) & 0o777:
            raise LibraryError("Workspace: Installed resources changed; preserve and inspect them before loading.")
    manifest = release["Manifest"]
    prefix = f".specify/extensions/{request.identity}/resources/library/"
    guidance = [prefix + manifest["Root"]["Folder"] + "/SKILL.md"]
    guidance.extend(prefix + item["NativeFolder"] + "/SKILL.md" for item in manifest["Components"] if item["Id"] != request.identity)
    instructions = []
    resources = []
    for item in manifest["Payload"]:
        path = prefix + item["SourcePath"]
        reasons = [reason for reason in item["Reasons"] if reason["Kind"] == "external-instruction"]
        if reasons:
            instructions.append({"Path": path, "Purposes": [reason.get("LoadingPurpose", "") for reason in reasons]})
        elif path not in guidance:
            resources.append(path)
    return {"Action": "Load", "Skill": _summary(release), "Request": " ".join(request.query), "Guidance": guidance, "Instructions": instructions, "Resources": resources}


def dispatch(request: LibraryRequest, catalog_path: Path, artifacts: Path, workspace: Path) -> dict[str, Any]:
    """Resolve discovery and exact releases from verified bundled artifacts only."""
    if request.action == "Help":
        return {"Action": "Help", "Command": "/speckit-skill-library", "Operations": ["search", "install", "list --installed", "load"]}
    if request.action == "Installed":
        installed = _installed(workspace)
        return {"Action": "Installed", "Skills": [{"Id": identity, "Version": record["version"], "Enabled": record["enabled"]} for identity, record in sorted(installed.items()) if identity != "skill"]}
    catalog = _catalog(catalog_path)
    if request.action == "Load":
        return _load(request, workspace, catalog, artifacts)
    if request.action == "Install":
        return _workspace_operation(request, catalog, catalog_path, artifacts, workspace)
    if request.action in {"Search", "Discover"}:
        query = " ".join(request.query)
        if request.action == "Discover" and query in catalog["skills"]:
            return {"Action": "Details", "Skill": _summary(_release(catalog, artifacts, query))}
        matches = []
        terms = query.casefold().split()
        for identity in sorted(catalog["skills"]):
            release = _release(catalog, artifacts, identity)
            text = " ".join([release["Id"], release["Name"], release["Description"], *release["Facets"]]).casefold()
            if all(term in text for term in terms):
                matches.append(_summary(release))
        return {"Action": "Search", "Matches": matches, "Message": "" if matches else "Sorry, we can't find that skill."}
    raise LibraryError("Workspace: This operation requires a compatible installed consumer.")


def main() -> int:
    """Translate command failures into bounded JSON without raw diagnostics."""
    try:
        parser = LibraryParser(add_help=False, allow_abbrev=False)
        parser.add_argument("--catalog", type=Path, default=Path(__file__).parent.parent / "library/catalog.json")
        parser.add_argument("--artifacts", type=Path)
        parser.add_argument("--workspace", type=Path, default=Path.cwd())
        parser.add_argument("--package-selection", action="store_true")
        parser.add_argument("arguments", nargs=argparse.REMAINDER)
        configured = parser.parse_args(sys.argv[1:])
        arguments = configured.arguments[1:] if configured.arguments[:1] == ["--"] else configured.arguments
        request = parse_arguments(arguments)
        artifacts = configured.artifacts or configured.catalog.parent / "packages"
        result = _package_selection(request, configured.catalog, artifacts) if configured.package_selection else dispatch(request, configured.catalog, artifacts, configured.workspace)
        sys.stdout.write(json.dumps(result, separators=(",", ":")) + "\n")
        if result.get("Action") == "Preview":
            return 0 if result["Preview"].get("Ready") is True else 2
        if result.get("Action") == "Apply":
            operation = result["Result"]
            return 0 if operation.get("State") == "Completed" else 3 if operation.get("MutationBegan") or operation.get("OperationPath") else 2
        return 0
    except LibraryError as error:
        sys.stdout.write(json.dumps({"Action": "Unknown" if error.exit_code == 3 else "Blocked", "Message": str(error)}, separators=(",", ":")) + "\n")
        return error.exit_code
    except Exception:
        sys.stdout.write('{"Action":"Blocked","Message":"Artifact: Revalidate the bundled catalog, artifacts and installed prerequisites."}\n')
        return 2


if __name__ == "__main__":
    sys.exit(main())
