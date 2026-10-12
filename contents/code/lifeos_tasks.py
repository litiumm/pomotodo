#!/usr/bin/env python3
"""Print open Obsidian Tasks from a vault as JSON, for the PomoTodo widget.

Mirrors the LifeOS Dashboard query: not done, path does not include
Templates, sort by due (then priority, then file order).
"""
import datetime
import json
import os
import re
import sys

TASK_RE = re.compile(r"^\s*[-*+] \[([ /])\]\s+(.*)$")
DUE_RE = re.compile(r"📅\s*(\d{4}-\d{2}-\d{2})")
SCHEDULED_RE = re.compile(r"⏳\s*(\d{4}-\d{2}-\d{2})")
PRIORITIES = {"🔺": 0, "⏫": 1, "🔼": 2, "🔽": 4, "⏬": 5}  # none = 3
# Tasks plugin metadata: emoji followed by its value
META_RE = re.compile(
    r"\s*(?:[📅⏳🛫➕✅❌]️?\s*\d{4}-\d{2}-\d{2}"
    r"|🔁️?[^📅⏳🛫➕✅❌🆔⛔🔺⏫🔼🔽⏬]*"
    r"|🆔\s*\S+|⛔\s*[\w,\s-]+|[🔺⏫🔼🔽⏬]️?)"
)
SKIP_DIRS = {".obsidian", ".git", ".stfolder", ".trash", "Templates"}


def clean(text):
    text = META_RE.sub("", text)
    text = re.sub(r"\[\[([^\]|]+)\|([^\]]+)\]\]", r"\2", text)  # [[a|b]] -> b
    text = re.sub(r"\[\[([^\]]+)\]\]", r"\1", text)  # [[a]] -> a
    text = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", text)  # [a](url) -> a
    text = re.sub(r"(\*\*|__|~~|==|`)", "", text)
    text = re.sub(r"\^[\w-]+\s*$", "", text)  # block ids
    return " ".join(text.split())


def scan(vault):
    tasks = []
    for root, dirs, files in os.walk(vault):
        dirs[:] = sorted(d for d in dirs if d not in SKIP_DIRS)
        for name in sorted(files):
            if not name.endswith(".md"):
                continue
            path = os.path.join(root, name)
            try:
                with open(path, encoding="utf-8") as f:
                    lines = f.readlines()
            except (OSError, UnicodeDecodeError):
                continue
            for lineno, line in enumerate(lines, 1):
                m = TASK_RE.match(line)
                if not m:
                    continue
                raw = m.group(2)
                text = clean(raw)
                if not text:
                    continue
                due = DUE_RE.search(raw)
                sched = SCHEDULED_RE.search(raw)
                prio = next((p for e, p in PRIORITIES.items() if e in raw), 3)
                tasks.append({
                    "text": text,
                    "due": due.group(1) if due else "",
                    "scheduled": sched.group(1) if sched else "",
                    "priority": prio,
                    "inProgress": m.group(1) == "/",
                    "file": path,
                    "note": os.path.splitext(name)[0],
                    "line": lineno,
                })
    tasks.sort(key=lambda t: (t["due"] or "9999-99-99", t["priority"]))
    return tasks


def main():
    vault = os.path.expanduser(sys.argv[1] if len(sys.argv) > 1 else "~/LifeOS")
    out = {"today": datetime.date.today().isoformat(), "vault": vault}
    if not os.path.isdir(vault):
        out.update(error="Vault not found: " + vault, tasks=[])
    else:
        out["tasks"] = scan(vault)
    print(json.dumps(out, ensure_ascii=False))


if __name__ == "__main__":
    main()
