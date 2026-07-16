#!/usr/bin/env python3
"""Validate the repository-local Codex skill package without third-party modules."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SKILLS_DIR = ROOT / ".agents" / "skills"
NAME_RE = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
FRONTMATTER_KEYS = {"name", "description"}
SCAFFOLD_MARKERS = (
    "[todo:",
    "structuring this skill",
    "replace with the first main section",
)


class ValidationError(Exception):
    """Report one invalid skill artifact."""


def parse_scalar(value: str, path: Path, key: str) -> str:
    value = value.strip()
    if not value:
        raise ValidationError(f"{path}: {key} must not be empty")

    if value[0] in "[{|>":
        raise ValidationError(f"{path}: {key} must be a single-line YAML string")

    if value[0] == '"':
        try:
            parsed = json.loads(value)
        except json.JSONDecodeError as exc:
            raise ValidationError(f"{path}: invalid quoted {key}: {exc}") from exc
        if not isinstance(parsed, str):
            raise ValidationError(f"{path}: {key} must be a string")
        return parsed

    if value[0] == "'":
        if len(value) < 2 or value[-1] != "'":
            raise ValidationError(f"{path}: unterminated quoted {key}")
        return value[1:-1].replace("''", "'")

    return value


def parse_frontmatter(path: Path, content: str) -> dict[str, str]:
    if not content.startswith("---\n"):
        raise ValidationError(f"{path}: missing YAML frontmatter")

    try:
        block, _ = content[4:].split("\n---\n", 1)
    except ValueError as exc:
        raise ValidationError(f"{path}: unterminated YAML frontmatter") from exc

    values: dict[str, str] = {}
    for line in block.splitlines():
        if not line.strip():
            continue
        if line[:1].isspace() or ":" not in line:
            raise ValidationError(f"{path}: frontmatter must use simple top-level scalars")
        key, raw_value = line.split(":", 1)
        if key in values:
            raise ValidationError(f"{path}: duplicate frontmatter key {key!r}")
        values[key] = parse_scalar(raw_value, path, key)

    if set(values) != FRONTMATTER_KEYS:
        missing = sorted(FRONTMATTER_KEYS - set(values))
        extra = sorted(set(values) - FRONTMATTER_KEYS)
        raise ValidationError(f"{path}: frontmatter keys mismatch; missing={missing}, extra={extra}")

    return values


def parse_interface(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    lines = path.read_text(encoding="utf-8").splitlines()
    if not lines or lines[0] != "interface:":
        raise ValidationError(f"{path}: expected a top-level interface mapping")

    for line in lines[1:]:
        if not line.strip():
            continue
        match = re.fullmatch(r'  ([a-z_]+): ("(?:[^"\\]|\\.)*")', line)
        if match is None:
            raise ValidationError(f"{path}: expected quoted interface string, got {line!r}")
        key, raw_value = match.groups()
        if key in values:
            raise ValidationError(f"{path}: duplicate interface key {key!r}")
        values[key] = json.loads(raw_value)

    expected = {"display_name", "short_description", "default_prompt"}
    if set(values) != expected:
        missing = sorted(expected - set(values))
        extra = sorted(set(values) - expected)
        raise ValidationError(f"{path}: interface keys mismatch; missing={missing}, extra={extra}")

    return values


def validate_skill(skill_dir: Path) -> None:
    skill_md = skill_dir / "SKILL.md"
    if not skill_md.is_file():
        raise ValidationError(f"{skill_dir}: missing SKILL.md")

    content = skill_md.read_text(encoding="utf-8")
    frontmatter = parse_frontmatter(skill_md, content)
    name = frontmatter["name"].strip()
    description = frontmatter["description"].strip()

    if name != skill_dir.name:
        raise ValidationError(f"{skill_md}: name {name!r} does not match folder {skill_dir.name!r}")
    if NAME_RE.fullmatch(name) is None or len(name) > 64:
        raise ValidationError(f"{skill_md}: invalid skill name {name!r}")
    if len(description) > 1024 or "<" in description or ">" in description:
        raise ValidationError(f"{skill_md}: description violates length or angle-bracket rules")

    lowered = content.lower()
    for marker in SCAFFOLD_MARKERS:
        if marker in lowered:
            raise ValidationError(f"{skill_md}: scaffold marker remains: {marker!r}")

    if content.count("```") % 2 != 0:
        raise ValidationError(f"{skill_md}: unbalanced fenced code block")
    if len(content.splitlines()) > 500:
        raise ValidationError(f"{skill_md}: exceeds the 500-line skill budget")

    for reference in re.findall(r"`(references/[^`]+)`", content):
        if not (skill_dir / reference).is_file():
            raise ValidationError(f"{skill_md}: missing referenced file {reference!r}")

    interface_path = skill_dir / "agents" / "openai.yaml"
    if not interface_path.is_file():
        raise ValidationError(f"{skill_dir}: missing agents/openai.yaml")
    interface = parse_interface(interface_path)

    short_description = interface["short_description"]
    if not 25 <= len(short_description) <= 64:
        raise ValidationError(
            f"{interface_path}: short_description must be 25-64 characters, got {len(short_description)}"
        )
    if f"${name}" not in interface["default_prompt"]:
        raise ValidationError(f"{interface_path}: default_prompt must mention ${name}")


def main() -> int:
    if not SKILLS_DIR.is_dir():
        print(f"error: skill directory not found: {SKILLS_DIR}", file=sys.stderr)
        return 1

    skill_dirs = sorted(path for path in SKILLS_DIR.iterdir() if path.is_dir())
    if not skill_dirs:
        print(f"error: no skills found under {SKILLS_DIR}", file=sys.stderr)
        return 1

    errors: list[str] = []
    for skill_dir in skill_dirs:
        try:
            validate_skill(skill_dir)
        except (OSError, ValidationError) as exc:
            errors.append(str(exc))

    if errors:
        for error in errors:
            print(f"error: {error}", file=sys.stderr)
        return 1

    print(f"validated {len(skill_dirs)} skills")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
