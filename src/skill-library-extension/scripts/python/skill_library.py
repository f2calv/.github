#!/usr/bin/env python3
"""Search, install and load skills from the skill library catalog through the Specify CLI.

The Python variant of the ``skill`` bootstrap helper. It behaves exactly like
``Invoke-SkillLibrary.ps1`` and ``bash/skill-library.sh``: same commands, arguments, output and
``.specify/extensions/.skill-library.json`` state, so a workspace can switch variants at any time.

After every install, upgrade, removal and prune the helper copies each enabled skill's
``resources/.github/`` into the workspace ``.github/``, where Copilot discovers skills and
instructions. It records each copy's SHA-256 and replaces or deletes a copy only while its bytes
still match, so local edits are kept and reported. Spec Kit cannot block ``specify extension add``,
``remove``, ``enable`` or ``disable`` on a skill, so every command except ``help`` first warns about
skills changed that way since the helper last recorded them.

Example:
    python3 skill_library.py install patterns-ports-and-adapters -Related patterns-modular-monolith

"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import urllib.request
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

BOOTSTRAP_ID = "skill"
DEFAULT_CATALOG = "https://f2calv.github.io/.github/catalog.json"
COMMANDS = ("help", "search", "plan", "install", "upgrade-all", "remove", "prune", "sync", "list", "load")
STATE_FILE = ".specify/extensions/.skill-library.json"
STATE_SCHEMA = "1.2"
REGISTRY_FILE = ".specify/extensions/.registry"
MANAGE_HINT = "Manage skills with /speckit-skill-library instead of specify extension add, remove, enable or disable."

Json = dict[str, Any]


class HelperError(Exception):
    """A failure reported to the user as a single message with exit code 1."""


@dataclass(frozen=True, slots=True)
class Release:
    """One catalog version of a skill with its dependency edges."""

    id: str
    version: str
    description: str
    required: list[Json]
    related: list[Json]


@dataclass(frozen=True, slots=True)
class Context:
    """Parsed arguments shared by every command."""

    command: str
    target: str
    version: str
    related: list[str]
    catalog_url: str
    workspace: Path


@dataclass(frozen=True, slots=True)
class Wanted:
    """A file an enabled skill ships under resources/.github/."""

    source: Path
    skill: str
    version: str
    digest: str


@dataclass(frozen=True, slots=True)
class Plan:
    """An install order with related offers."""

    steps: list[dict[str, str]]
    offers: list[dict[str, str]]


def emit(*lines: str) -> None:
    """Write command output lines to stdout."""
    for line in lines:
        sys.stdout.write(f"{line}\n")
    sys.stdout.flush()


def format_table(rows: list[dict[str, str]], columns: list[str]) -> str:
    """Render rows as a left-aligned table with a dashed header rule, like Format-Table."""
    widths = {column: max([len(column), *(len(row[column]) for row in rows)]) for column in columns}
    lines = [
        " ".join(column.ljust(widths[column]) for column in columns).rstrip(),
        " ".join(("-" * len(column)).ljust(widths[column]) for column in columns).rstrip(),
    ]
    lines.extend(" ".join(row[column].ljust(widths[column]) for column in columns).rstrip() for row in rows)
    return "\n" + "\n".join(lines) + "\n"


def read_json(path: Path) -> Json:
    """Read a UTF-8 JSON object from a file."""
    data: Json = json.loads(path.read_text(encoding="utf-8-sig"))
    return data


def get_catalog(ctx: Context) -> Json:
    """Load the catalog's extensions from a local file or an HTTP(S) URL."""
    local = Path(ctx.catalog_url)
    if local.is_file():
        extensions: Json = read_json(local)["extensions"]
        return extensions
    if not ctx.catalog_url.startswith(("https://", "http://")):
        message = f"Catalog '{ctx.catalog_url}' is neither a file nor an HTTP(S) URL."
        raise HelperError(message)
    with urllib.request.urlopen(ctx.catalog_url, timeout=60) as response:  # noqa: S310 - scheme checked above
        data: Json = json.loads(response.read().decode("utf-8"))
    remote: Json = data["extensions"]
    return remote


def get_installed(ctx: Context) -> Json:
    """Return Spec Kit's registry of installed extensions."""
    registry = ctx.workspace / REGISTRY_FILE
    if not registry.is_file():
        return {}
    installed: Json = read_json(registry).get("extensions") or {}
    return installed


def read_state(ctx: Context) -> tuple[Json, Json]:
    """Return the recorded skill choices and copied-file records."""
    path = ctx.workspace / STATE_FILE
    if not path.is_file():
        return {}, {}
    data = read_json(path)
    return data.get("skills") or {}, data.get("files") or {}


def is_skill_extension(ctx: Context, skill_id: str) -> bool:
    """Return whether an installed extension ships skill guidance under resources/.github/."""
    return skill_id != BOOTSTRAP_ID and (ctx.workspace / ".specify/extensions" / skill_id / "resources/.github").is_dir()


def save_state(ctx: Context, skills: Json, files: Json) -> None:
    """Write the state file, recording every installed skill with its version and enabled flag."""
    installed = get_installed(ctx)
    ids = {skill_id for skill_id in skills if skill_id in installed}
    ids.update(skill_id for skill_id in installed if is_skill_extension(ctx, skill_id))
    kept = {
        skill_id: {
            "chosen": is_chosen(skills, skill_id),
            "version": str(installed[skill_id].get("version", "")),
            "enabled": installed[skill_id].get("enabled") is not False,
        }
        for skill_id in sorted(ids)
    }
    copies = {rel: files[rel] for rel in sorted(files)}
    path = ctx.workspace / STATE_FILE
    path.parent.mkdir(parents=True, exist_ok=True)
    document = {"schema_version": STATE_SCHEMA, "skills": kept, "files": copies}
    path.write_text(json.dumps(document, indent=2) + "\n", encoding="utf-8")


def entry_drift(skill_id: str, entry: Json, version: str, *, enabled: bool) -> list[str]:
    """Compare one recorded skill with its registry version and enabled flag."""
    lines = []
    if "version" in entry and str(entry["version"]) != version:
        lines.append(
            f"Warning: {skill_id} changed from {entry['version']} to {version} outside the skill library. "
            "Run sync to update its guidance in .github/.",
        )
    if "enabled" in entry and bool(entry["enabled"]) != enabled:
        if enabled:
            lines.append(f"Warning: {skill_id} was enabled outside the skill library. Run sync to copy its guidance into .github/.")
        else:
            lines.append(f"Warning: {skill_id} was disabled outside the skill library. Run sync to delete its guidance from .github/.")
    return lines


def drift_warnings(ctx: Context) -> list[str]:
    """Report skills that direct specify extension commands changed; Spec Kit cannot block them."""
    path = ctx.workspace / STATE_FILE
    if not path.is_file():
        return []
    data = read_json(path)
    skills: Json = data.get("skills") or {}
    # Before schema 1.2 the state did not record every installed skill, so an unrecorded one is not evidence of drift.
    complete = data.get("schema_version") == STATE_SCHEMA
    installed = get_installed(ctx)
    lines: list[str] = []
    for skill_id in sorted(set(skills) | {item for item in installed if is_skill_extension(ctx, item)}):
        if skill_id not in installed:
            lines.append(
                f"Warning: {skill_id} was removed outside the skill library. "
                f"Run install {skill_id} to restore it, or sync to delete its guidance from .github/.",
            )
            continue
        version = str(installed[skill_id].get("version", ""))
        if skill_id not in skills:
            if complete:
                lines.append(
                    f"Warning: {skill_id} {version} was installed outside the skill library. Run sync to copy its guidance into .github/.",
                )
            continue
        lines.extend(entry_drift(skill_id, skills[skill_id], version, enabled=installed[skill_id].get("enabled") is not False))
    if lines:
        lines.append(MANAGE_HINT)
    return lines


def save_manifest(ctx: Context, skills: Json) -> None:
    """Save skill choices while preserving copied-file records."""
    save_state(ctx, skills, read_state(ctx)[1])


def sha256(path: Path) -> str:
    """Return the lowercase SHA-256 of a file."""
    return hashlib.sha256(path.read_bytes()).hexdigest()


def utc_now() -> str:
    """Return the current UTC time as an ISO 8601 string with a Z suffix."""
    return datetime.now(UTC).strftime("%Y-%m-%dT%H:%M:%SZ")


def remove_empty_parents(ctx: Context, path: Path) -> None:
    """Delete empty folders above a removed copy, stopping at the workspace .github/."""
    stop = (ctx.workspace / ".github").resolve()
    folder = path.resolve().parent
    while folder != stop and stop in folder.parents and not any(folder.iterdir()):
        folder.rmdir()
        folder = folder.parent


def desired_guidance(ctx: Context, notes: list[str]) -> dict[str, Wanted]:
    """Collect every enabled skill's guidance files; the first skill by ID wins a shared path."""
    installed = get_installed(ctx)
    desired: dict[str, Wanted] = {}
    for skill_id in sorted(installed):
        if skill_id == BOOTSTRAP_ID or installed[skill_id].get("enabled") is False:
            continue
        root = ctx.workspace / ".specify/extensions" / skill_id / "resources/.github"
        if not root.is_dir():
            continue
        for source in sorted(item for item in root.rglob("*") if item.is_file()):
            rel = ".github/" + source.relative_to(root).as_posix()
            digest = sha256(source)
            if rel in desired:
                if desired[rel].digest != digest:
                    notes.append(f"Kept {rel} from {desired[rel].skill}; {skill_id} ships a different copy.")
                continue
            desired[rel] = Wanted(source, skill_id, str(installed[skill_id].get("version", "")), digest)
    return desired


def apply_wanted(ctx: Context, rel: str, want: Wanted, record: Json | None, notes: list[str]) -> tuple[Json | None, str]:
    """Copy one wanted file unless a local edit or unmanaged file must be kept."""
    path = ctx.workspace / rel
    current = sha256(path) if path.is_file() else None
    new_record = {"sha256": want.digest, "skill": want.skill, "version": want.version, "copied": utc_now()}
    if current == want.digest:
        return (record if record and record.get("sha256") == want.digest else new_record), ""
    if current and not record:
        notes.append(f"Kept {rel}: it exists and was not copied by the skill library.")
        return None, ""
    if current and record and current != record.get("sha256"):
        notes.append(
            f"Kept {rel}: modified since {record.get('skill')} {record.get('version')} copied it on "
            f"{record.get('copied')}; {want.skill} {want.version} was not applied.",
        )
        return record, ""
    path.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(want.source, path)
    return new_record, ("updated" if current else "copied")


def remove_stale_copy(ctx: Context, rel: str, record: Json, notes: list[str]) -> bool:
    """Delete a copy no skill ships any more, unless it was modified; return whether it was deleted."""
    if not rel.startswith(".github/") or ".." in rel.split("/"):
        return False
    path = ctx.workspace / rel
    if not path.is_file():
        return False
    if sha256(path) != record.get("sha256"):
        notes.append(
            f"Kept {rel}: modified since {record.get('skill')} {record.get('version')} copied it on "
            f"{record.get('copied')}. Review it before deleting it.",
        )
        return False
    path.unlink()
    remove_empty_parents(ctx, path)
    return True


def sync_guidance(ctx: Context) -> None:
    """Mirror enabled skills' resources/.github/ into .github/, touching only unmodified copies."""
    skills, records = read_state(ctx)
    notes: list[str] = []
    desired = desired_guidance(ctx, notes)
    following: Json = {}
    counts = {"copied": 0, "updated": 0, "removed": 0}
    for rel, want in desired.items():
        record, action = apply_wanted(ctx, rel, want, records.get(rel), notes)
        if record is not None:
            following[rel] = record
        if action:
            counts[action] += 1
    for rel in sorted(records):
        if rel not in desired and remove_stale_copy(ctx, rel, records[rel], notes):
            counts["removed"] += 1
    save_state(ctx, skills, following)
    emit(f"Guidance in .github/: {counts['copied']} copied, {counts['updated']} updated, {counts['removed']} removed.")
    emit(*notes)


def run_specify(ctx: Context, arguments: list[str], env: dict[str, str] | None = None) -> int:
    """Run the Specify CLI in the workspace and return its exit code."""
    executable = shutil.which("specify")
    if executable is None:
        message = "The specify CLI is not on PATH."
        raise HelperError(message)
    emit("specify " + " ".join(arguments))
    completed = subprocess.run([executable, *arguments], cwd=ctx.workspace, env=env, check=False)  # noqa: S603 - fixed CLI with an argument list
    return completed.returncode


def invoke_remove(ctx: Context, skill_ids: list[str]) -> None:
    """Remove extensions through specify, stopping at the first failure."""
    for skill_id in skill_ids:
        if run_specify(ctx, ["extension", "remove", skill_id, "--force"]) != 0:
            message = f"Removing {skill_id} failed; skills listed before it were removed."
            raise HelperError(message)
    save_manifest(ctx, read_state(ctx)[0])


def is_chosen(manifest: Json, skill_id: str) -> bool:
    """Treat skills installed before choices were recorded as chosen, so they are never pruned."""
    if skill_id not in manifest:
        return True
    return bool(manifest[skill_id].get("chosen"))


def get_release(catalog: Json, skill_id: str, exact: str) -> Release:
    """Return the current or an exact release of a skill from the catalog."""
    if skill_id not in catalog:
        message = f"Sorry, we can't find the skill '{skill_id}'."
        raise HelperError(message)
    entry = catalog[skill_id]
    if not exact or exact == entry["version"]:
        record = entry
    elif exact in (entry.get("releases") or {}):
        record = entry["releases"][exact]
    else:
        message = f"Version {exact} of '{skill_id}' is not available."
        raise HelperError(message)
    library = record.get("skill_library") or {}
    return Release(
        id=skill_id,
        version=exact or entry["version"],
        description=entry.get("description", ""),
        required=list(library.get("required") or []),
        related=list(library.get("related") or []),
    )


def get_installed_release(catalog: Json, skill_id: str, version: str) -> Release:
    """Return the installed release, or the current one when that version left the catalog."""
    try:
        return get_release(catalog, skill_id, version)
    except HelperError:
        return get_release(catalog, skill_id, "")


def required_ids(catalog: Json, installed: Json, skill_id: str) -> set[str]:
    """Return the IDs the installed version of a skill requires."""
    release = get_installed_release(catalog, skill_id, str(installed[skill_id].get("version", "")))
    return {edge["id"] for edge in release.required}


def get_unneeded(ctx: Context, catalog: Json) -> list[str]:
    """Return installed skills that no chosen skill requires."""
    installed = get_installed(ctx)
    manifest = read_state(ctx)[0]
    needed: set[str] = set()
    pending = [skill_id for skill_id in installed if skill_id != BOOTSTRAP_ID and is_chosen(manifest, skill_id)]
    while pending:
        skill_id = pending.pop()
        if skill_id in needed or skill_id not in installed or skill_id not in catalog:
            continue
        needed.add(skill_id)
        pending.extend(required_ids(catalog, installed, skill_id))
    return sorted(skill_id for skill_id in installed if skill_id != BOOTSTRAP_ID and skill_id in catalog and skill_id not in needed)


def show_unneeded(skill_ids: list[str]) -> None:
    """Report skills that prune would remove."""
    if skill_ids:
        emit(f"No longer required by any chosen skill: {', '.join(skill_ids)}. Run prune to remove them.")


def plan_action(installed: Json, skill_id: str, version: str) -> str:
    """Describe what installing one skill version would do."""
    if skill_id not in installed:
        return "install"
    current = installed[skill_id].get("version")
    return "installed" if current == version else f"conflict: {current} installed"


def resolve_plan(ctx: Context, catalog: Json) -> Plan:
    """Resolve the target, its required closure and selected related skills."""
    installed = get_installed(ctx)
    order: list[dict[str, str]] = []
    chosen: dict[str, Release] = {}

    def add_skill(skill_id: str, exact: str, reason: str) -> None:
        if skill_id in chosen:
            if exact and chosen[skill_id].version != exact:
                message = f"Conflicting versions of '{skill_id}': {chosen[skill_id].version} and {exact}."
                raise HelperError(message)
            return
        release = get_release(catalog, skill_id, exact)
        chosen[skill_id] = release
        for edge in release.required:
            add_skill(edge["id"], edge["version"], f"required by {skill_id}")
        action = plan_action(installed, skill_id, release.version)
        order.append({"Id": skill_id, "Version": release.version, "Reason": reason, "Action": action})

    add_skill(ctx.target, ctx.version, "requested")
    for skill_id in ctx.related:
        add_skill(skill_id, "", "related, selected")
    offers: dict[tuple[str, str], dict[str, str]] = {}
    for release in chosen.values():
        for edge in release.related:
            if edge["id"] not in chosen:
                state = "installed" if edge["id"] in installed else "not installed"
                offers[(edge["id"], release.id)] = {
                    "Id": edge["id"],
                    "OfferedBy": release.id,
                    "Reason": edge.get("reason", ""),
                    "State": state,
                }
    return Plan(order, [offers[key] for key in sorted(offers)])


def show_plan(plan: Plan) -> None:
    """Print the install order and related offers."""
    emit("Install order:", format_table(plan.steps, ["Id", "Version", "Action", "Reason"]))
    if plan.offers:
        emit("Related skills you can add with -Related:", format_table(plan.offers, ["Id", "State", "OfferedBy", "Reason"]))


def version_key(version: str) -> tuple[int, ...]:
    """Return a numeric sort key for an X.Y.Z version."""
    return tuple(int(part) for part in version.split("."))


def upgrade_action(installed: Json, skill_id: str, version: str) -> str:
    """Describe what upgrading one skill to a version would do."""
    if skill_id not in installed:
        return "install"
    current = str(installed[skill_id].get("version"))
    if current == version:
        return "current"
    if version_key(current) > version_key(version):
        return f"newer {current} installed"
    return f"upgrade from {current}"


def resolve_upgrade(ctx: Context, catalog: Json) -> list[dict[str, str]]:
    """Return every installed skill's upgrade step, required skills first."""
    installed = get_installed(ctx)
    targets = {skill_id: get_release(catalog, skill_id, "") for skill_id in installed if skill_id != BOOTSTRAP_ID and skill_id in catalog}
    steps: list[dict[str, str]] = []
    visited: set[str] = set()

    def add_step(release: Release) -> None:
        if release.id in visited:
            return
        visited.add(release.id)
        for edge in release.required:
            if edge["id"] not in targets:
                targets[edge["id"]] = get_release(catalog, edge["id"], edge["version"])
            if targets[edge["id"]].version != edge["version"]:
                message = (
                    f"{release.id} {release.version} requires {edge['id']} {edge['version']}, "
                    f"but the latest is {targets[edge['id']].version}. Nothing was changed."
                )
                raise HelperError(message)
            add_step(targets[edge["id"]])
        steps.append({"Id": release.id, "Version": release.version, "Action": upgrade_action(installed, release.id, release.version)})

    for skill_id in sorted(targets):
        add_step(targets[skill_id])
    return steps


def invoke_specify(ctx: Context, steps: list[dict[str, str]]) -> None:
    """Install or upgrade each step through specify with this helper's catalog."""
    digest = hashlib.sha256(ctx.catalog_url.encode("utf-8")).hexdigest()[:16]
    cache = ctx.workspace / ".specify/extensions/.cache"
    if cache.is_dir():
        for stale in cache.glob(f"catalog-{digest}*.json"):
            stale.unlink()
    env = {**os.environ, "SPECKIT_CATALOG_URL": ctx.catalog_url}
    for step in steps:
        arguments = ["extension", "add", step["Id"], "--version", step["Version"]]
        if step["Action"].startswith("upgrade"):
            arguments.append("--force")
        if run_specify(ctx, arguments, env) != 0:
            message = f"Installing {step['Id']} {step['Version']} failed; earlier skills in the order remain installed."
            raise HelperError(message)


def require_target(ctx: Context) -> None:
    """Fail when a command that needs a skill ID got none."""
    if not ctx.target:
        message = f"The {ctx.command} command needs a skill ID."
        raise HelperError(message)


def command_help(_: Context) -> None:
    """List commands."""
    emit(
        "Commands: search <terms> | plan <id> | install <id> [-Version X.Y.Z] [-Related a,b] | upgrade-all | "
        "remove <id> | prune | sync | list | load <id>",
    )


def command_search(ctx: Context) -> None:
    """Find skills by ID, description or facet."""
    terms = ctx.target.lower().split()
    rows = []
    for skill_id, entry in sorted(get_catalog(ctx).items()):
        if skill_id == BOOTSTRAP_ID:
            continue
        tags = list(entry.get("tags") or [])
        text = " ".join([skill_id, entry.get("description", ""), *tags]).lower()
        if all(term in text for term in terms):
            rows.append(
                {"Id": skill_id, "Version": entry["version"], "Facets": ", ".join(tags), "Description": entry.get("description", "")}
            )
    if not rows:
        emit(f"Sorry, we can't find a skill matching '{ctx.target}'.")
    else:
        emit(format_table(rows, ["Id", "Version", "Facets", "Description"]))


def command_plan(ctx: Context) -> None:
    """Show the install order and offers without changing anything."""
    require_target(ctx)
    show_plan(resolve_plan(ctx, get_catalog(ctx)))


def command_install(ctx: Context) -> None:
    """Install the target, its required skills and selected related skills."""
    require_target(ctx)
    plan = resolve_plan(ctx, get_catalog(ctx))
    show_plan(plan)
    conflicts = [step["Id"] for step in plan.steps if step["Action"].startswith("conflict")]
    if conflicts:
        message = f"Resolve version conflicts first: {', '.join(conflicts)}. Nothing was installed."
        raise HelperError(message)
    invoke_specify(ctx, [step for step in plan.steps if step["Action"] == "install"])
    manifest = read_state(ctx)[0]
    for step in plan.steps:
        if step["Reason"] in ("requested", "related, selected"):
            manifest[step["Id"]] = {"chosen": True}
        elif step["Action"] == "install" and step["Id"] not in manifest:
            manifest[step["Id"]] = {"chosen": False}
    save_manifest(ctx, manifest)
    sync_guidance(ctx)
    emit("Installed. Run plan for newly installed related skills to see their related offers.")


def previous_related(catalog: Json, skill_id: str, before: Json) -> set[str]:
    """Return the related IDs of the version installed before an upgrade."""
    if skill_id not in before:
        return set()
    try:
        return {edge["id"] for edge in get_release(catalog, skill_id, str(before[skill_id].get("version"))).related}
    except HelperError:
        return set()


def new_related_offers(catalog: Json, pending: list[dict[str, str]], before: Json, installed: Json) -> list[dict[str, str]]:
    """Return related skills an upgraded version newly lists and that are not installed."""
    offers: dict[tuple[str, str], dict[str, str]] = {}
    for step in pending:
        previous = previous_related(catalog, step["Id"], before)
        for edge in get_release(catalog, step["Id"], step["Version"]).related:
            if edge["id"] not in previous and edge["id"] not in installed:
                offers[(edge["id"], step["Id"])] = {"Id": edge["id"], "OfferedBy": step["Id"], "Reason": edge.get("reason", "")}
    return [offers[key] for key in sorted(offers)]


def apply_upgrades(ctx: Context, catalog: Json, pending: list[dict[str, str]]) -> None:
    """Install pending steps, record newly required skills and offer newly related ones."""
    before = get_installed(ctx)
    invoke_specify(ctx, pending)
    manifest = read_state(ctx)[0]
    for step in pending:
        if step["Action"] == "install" and step["Id"] not in manifest:
            manifest[step["Id"]] = {"chosen": False}
    save_manifest(ctx, manifest)
    emit(f"Upgraded {len(pending)} skill(s).")
    offers = new_related_offers(catalog, pending, before, get_installed(ctx))
    if offers:
        emit("New related skills you can add with install <id>:", format_table(offers, ["Id", "OfferedBy", "Reason"]))


def command_upgrade_all(ctx: Context) -> None:
    """Upgrade every installed skill, then offer new related skills and report unneeded ones."""
    catalog = get_catalog(ctx)
    steps = resolve_upgrade(ctx, catalog)
    if not steps:
        emit("No skills are installed.")
        sync_guidance(ctx)
        return
    emit("Upgrade order:", format_table(steps, ["Id", "Version", "Action"]))
    pending = [step for step in steps if step["Action"] == "install" or step["Action"].startswith("upgrade")]
    if pending:
        apply_upgrades(ctx, catalog, pending)
    else:
        emit("All installed skills are at their latest versions.")
    sync_guidance(ctx)
    show_unneeded(get_unneeded(ctx, catalog))


def command_remove(ctx: Context) -> None:
    """Remove one skill that no other installed skill requires."""
    require_target(ctx)
    if ctx.target == BOOTSTRAP_ID:
        message = f"Remove the bootstrap with: specify extension remove {BOOTSTRAP_ID}"
        raise HelperError(message)
    installed = get_installed(ctx)
    if ctx.target not in installed:
        message = f"'{ctx.target}' is not installed."
        raise HelperError(message)
    catalog = get_catalog(ctx)
    dependents = sorted(
        skill_id
        for skill_id in installed
        if skill_id not in (BOOTSTRAP_ID, ctx.target) and skill_id in catalog and ctx.target in required_ids(catalog, installed, skill_id)
    )
    if dependents:
        message = f"'{ctx.target}' is required by {', '.join(dependents)}. Remove those first. Nothing was changed."
        raise HelperError(message)
    invoke_remove(ctx, [ctx.target])
    sync_guidance(ctx)
    show_unneeded(get_unneeded(ctx, catalog))


def command_prune(ctx: Context) -> None:
    """Remove installed skills that no chosen skill requires."""
    unneeded = get_unneeded(ctx, get_catalog(ctx))
    if not unneeded:
        emit("Nothing to prune: every installed skill is chosen or required by one.")
        return
    invoke_remove(ctx, unneeded)
    emit(f"Removed {len(unneeded)} skill(s).")
    sync_guidance(ctx)


def command_sync(ctx: Context) -> None:
    """Copy installed guidance into .github/ again."""
    sync_guidance(ctx)


def command_list(ctx: Context) -> None:
    """List installed skills, each marked chosen or required."""
    installed = get_installed(ctx)
    manifest = read_state(ctx)[0]
    rows = [
        {
            "Id": skill_id,
            "Version": str(entry.get("version", "")),
            "Enabled": str(entry.get("enabled", "")),
            "Source": "chosen" if is_chosen(manifest, skill_id) else "required",
        }
        for skill_id, entry in sorted(installed.items())
        if skill_id != BOOTSTRAP_ID and (ctx.workspace / ".specify/extensions" / skill_id / "resources").exists()
    ]
    if not rows:
        emit("No skills are installed.")
        return
    emit(format_table(rows, ["Id", "Version", "Enabled", "Source"]))
    show_unneeded(get_unneeded(ctx, get_catalog(ctx)))


def load_rank(rel: str) -> int:
    """Order SKILL.md first, then instructions, then everything else."""
    if rel.endswith("/SKILL.md"):
        return 0
    return 1 if rel.endswith(".instructions.md") else 2


def command_load(ctx: Context) -> None:
    """List a skill's installed files, SKILL.md first."""
    require_target(ctx)
    root = ctx.workspace / ".specify/extensions" / ctx.target / "resources"
    if not root.exists():
        message = f"'{ctx.target}' is not installed; run install first."
        raise HelperError(message)
    files = sorted(
        (item.relative_to(ctx.workspace).as_posix() for item in root.rglob("*") if item.is_file()),
        key=lambda rel: (load_rank(rel), rel),
    )
    emit(f"Installed files for {ctx.target} (read SKILL.md first, then instructions, then others as needed):", *files)


HANDLERS = {
    "help": command_help,
    "search": command_search,
    "plan": command_plan,
    "install": command_install,
    "upgrade-all": command_upgrade_all,
    "remove": command_remove,
    "prune": command_prune,
    "sync": command_sync,
    "list": command_list,
    "load": command_load,
}


def parse_arguments(argv: list[str], environ: dict[str, str]) -> Context:
    """Parse the same arguments as the PowerShell helper, including -Version and -Related."""
    parser = argparse.ArgumentParser(prog="skill_library.py", description="Search, install and load skills from the skill library catalog.")
    parser.add_argument("command", nargs="?", default="help", choices=COMMANDS)
    parser.add_argument("target", nargs="?", default="")
    parser.add_argument("-Version", "--version", dest="version", default="")
    parser.add_argument("-Related", "--related", dest="related", action="append", default=[])
    parser.add_argument(
        "-CatalogUrl", "--catalog-url", dest="catalog_url", default=environ.get("SKILL_LIBRARY_CATALOG_URL") or DEFAULT_CATALOG
    )
    parser.add_argument("-Workspace", "--workspace", dest="workspace", default=str(Path.cwd()))
    parsed = parser.parse_args(argv)
    related = [item.strip() for value in parsed.related for item in value.split(",") if item.strip()]
    return Context(parsed.command, parsed.target, parsed.version, related, parsed.catalog_url, Path(parsed.workspace))


def main(argv: list[str] | None = None) -> int:
    """Run one helper command and map failures to exit code 1."""
    ctx = parse_arguments(sys.argv[1:] if argv is None else argv, dict(os.environ))
    try:
        if ctx.command != "help":
            emit(*drift_warnings(ctx))
        HANDLERS[ctx.command](ctx)
    except HelperError as error:
        sys.stderr.write(f"{error}\n")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
