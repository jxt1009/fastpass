#!/usr/bin/env python3
"""Prepare plain-text TestFlight notes from markdown release notes."""

from __future__ import annotations

import argparse
import re
import sys

ALLOWED_SECTIONS = {
    "features": "Features",
    "bug fixes": "Bug Fixes",
    "performance": "Performance",
}
ORDERED_SECTIONS = ["Features", "Bug Fixes", "Performance"]
RELEASE_HEADER_RE = re.compile(r"^##\s+\[([^\]]+)\]")
SECTION_HEADER_RE = re.compile(r"^###\s+(.+?)\s*$")
LIST_ITEM_RE = re.compile(r"^[-*]\s+")


def _normalize_section_name(value: str) -> str:
    return re.sub(r"\s+", " ", value.strip().lower())


def _strip_markdown(value: str) -> str:
    text = value.replace("\r\n", "\n").replace("\r", "\n")
    text = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", text)
    text = re.sub(r"`([^`]*)`", r"\1", text)
    text = text.replace("**", "").replace("__", "")
    text = re.sub(r"<[^>]+>", "", text)
    return text.strip()


def _extract_latest_release_block(markdown: str) -> tuple[str | None, list[str]]:
    lines = markdown.splitlines()
    start = None
    version = None

    for i, line in enumerate(lines):
        match = RELEASE_HEADER_RE.match(line.strip())
        if match:
            start = i
            version = match.group(1).lstrip("v")
            break

    if start is None:
        return None, []

    end = len(lines)
    for i in range(start + 1, len(lines)):
        if RELEASE_HEADER_RE.match(lines[i].strip()):
            end = i
            break

    return version, lines[start:end]


def _build_testflight_notes(version: str | None, block_lines: list[str]) -> str:
    section_items: dict[str, list[str]] = {section: [] for section in ORDERED_SECTIONS}
    current_section: str | None = None

    for raw_line in block_lines[1:]:
        line = raw_line.strip()
        if not line:
            continue

        section_match = SECTION_HEADER_RE.match(line)
        if section_match:
            normalized = _normalize_section_name(_strip_markdown(section_match.group(1)))
            current_section = ALLOWED_SECTIONS.get(normalized)
            continue

        if current_section is None:
            continue

        if LIST_ITEM_RE.match(line):
            bullet = LIST_ITEM_RE.sub("", line, count=1)
            bullet = _strip_markdown(bullet)
            if bullet:
                section_items[current_section].append(f"- {bullet}")
            continue

        continuation = _strip_markdown(line)
        if continuation and section_items[current_section]:
            section_items[current_section][-1] = f"{section_items[current_section][-1]} {continuation}"

    output_lines: list[str] = []
    if version:
        output_lines.append(f"Version {version}")

    for section in ORDERED_SECTIONS:
        items = section_items[section]
        if not items:
            continue
        if output_lines:
            output_lines.append("")
        output_lines.append(f"{section}:")
        output_lines.extend(items)

    return "\n".join(output_lines).strip()


def _truncate(value: str, max_chars: int) -> str:
    if len(value) <= max_chars:
        return value
    if max_chars <= 1:
        return value[:max_chars]

    clipped = value[: max_chars - 1].rstrip()
    if "\n" in clipped:
        maybe_line_trimmed = clipped.rsplit("\n", 1)[0].rstrip()
        if maybe_line_trimmed:
            clipped = maybe_line_trimmed
    return f"{clipped}…"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--max-chars", type=int, default=4000)
    args = parser.parse_args()

    markdown = sys.stdin.read()
    version, latest_block = _extract_latest_release_block(markdown)
    if not latest_block:
        print("", end="")
        return 0

    notes = _build_testflight_notes(version, latest_block)
    if not notes:
        print("", end="")
        return 0

    print(_truncate(notes, args.max_chars), end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
