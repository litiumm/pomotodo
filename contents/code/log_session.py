#!/usr/bin/env python3
"""Append a finished pomodoro to the vault's daily note, for the PomoTodo widget.

Usage: log_session.py VAULT START_EPOCH END_EPOCH MINUTES [TASK]

Uses the core Daily notes settings (.obsidian/daily-notes.json) to find the
note for END's date, creating it from the daily template if it doesn't exist.
The entry goes at the end of the "Log" section, which is added if missing.
"""
import datetime
import json
import os
import re
import sys

LOG_HEADING = "## 📝 Log"
LOG_HEADING_RE = re.compile(r"^#{1,6}\s+.*\bLog\b", re.IGNORECASE)
HEADING_RE = re.compile(r"^#{1,6}\s")

# moment.js tokens used by Obsidian, longest first
MOMENT_TOKENS = [
    ("YYYY", "%Y"), ("YY", "%y"),
    ("MMMM", "%B"), ("MMM", "%b"), ("MM", "%m"),
    ("dddd", "%A"), ("ddd", "%a"),
    ("DD", "%d"), ("HH", "%H"), ("mm", "%M"), ("ss", "%S"),
]


def moment_format(dt, fmt):
    out, i = [], 0
    while i < len(fmt):
        if fmt[i] == "[":  # [literal]
            j = fmt.find("]", i)
            if j != -1:
                out.append(fmt[i + 1:j])
                i = j + 1
                continue
        for tok, strf in MOMENT_TOKENS:
            if fmt.startswith(tok, i):
                out.append(dt.strftime(strf))
                i += len(tok)
                break
        else:
            if fmt.startswith("D", i):
                out.append(str(dt.day))
            elif fmt.startswith("M", i):
                out.append(str(dt.month))
            else:
                out.append(fmt[i])
            i += 1
    return "".join(out)


def daily_settings(vault):
    try:
        with open(os.path.join(vault, ".obsidian", "daily-notes.json"), encoding="utf-8") as f:
            s = json.load(f)
    except (OSError, ValueError):
        s = {}
    return s.get("folder", ""), s.get("format") or "YYYY-MM-DD", s.get("template", "")


def from_template(vault, template, dt, title):
    if not template:
        return ""
    path = os.path.join(vault, template if template.endswith(".md") else template + ".md")
    try:
        with open(path, encoding="utf-8") as f:
            text = f.read()
    except OSError:
        return ""
    text = re.sub(r"\{\{\s*date:([^}]+)\}\}", lambda m: moment_format(dt, m.group(1).strip()), text)
    text = re.sub(r"\{\{\s*time:([^}]+)\}\}", lambda m: moment_format(dt, m.group(1).strip()), text)
    text = re.sub(r"\{\{\s*date\s*\}\}", dt.strftime("%Y-%m-%d"), text)
    text = re.sub(r"\{\{\s*time\s*\}\}", dt.strftime("%H:%M"), text)
    return re.sub(r"\{\{\s*title\s*\}\}", title, text)


def insert_entry(text, entry):
    lines = text.split("\n")
    if lines and lines[-1] == "":
        lines.pop()
    start = next((i for i, l in enumerate(lines) if LOG_HEADING_RE.match(l)), None)
    if start is None:
        if lines and lines[-1].strip():
            lines.append("")
        lines += [LOG_HEADING, entry]
        return "\n".join(lines) + "\n"
    end = next((i for i in range(start + 1, len(lines)) if HEADING_RE.match(lines[i])), len(lines))
    # after the last non-blank line of the section
    pos = start + 1
    for i in range(start + 1, end):
        if lines[i].strip():
            pos = i + 1
    lines.insert(pos, entry)
    return "\n".join(lines) + "\n"


def main():
    vault = os.path.expanduser(sys.argv[1])
    start = datetime.datetime.fromtimestamp(float(sys.argv[2]))
    end = datetime.datetime.fromtimestamp(float(sys.argv[3]))
    minutes = int(sys.argv[4])
    task = " ".join(sys.argv[5].split()) if len(sys.argv) > 5 else ""

    folder, fmt, template = daily_settings(vault)
    title = moment_format(end, fmt)
    path = os.path.join(vault, folder, title + ".md")

    if os.path.exists(path):
        with open(path, encoding="utf-8") as f:
            text = f.read()
    else:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        text = from_template(vault, template, end, os.path.basename(title))

    entry = "- %s–%s Pomodoro (%d min)%s" % (
        start.strftime("%H:%M"), end.strftime("%H:%M"), minutes, " · " + task if task else "")
    with open(path, "w", encoding="utf-8") as f:
        f.write(insert_entry(text, entry))
    print(path)


if __name__ == "__main__":
    main()
