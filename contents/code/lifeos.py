#!/usr/bin/env python3
"""Obsidian vault access for the PomoTodo widget.

  lifeos.py list   VAULT                          open tasks + tasks done today, as JSON
  lifeos.py toggle VAULT FILE LINE RAW            check/uncheck a task (RAW = the line's text)
  lifeos.py add    VAULT TEXT                     add a task to today's daily note
  lifeos.py log    VAULT START END MINUTES [TASK] log a finished pomodoro in the daily note

Tasks follow the LifeOS Dashboard query: not done, path does not include
Templates, sorted by due date then priority. Done dates use the Tasks
plugin's "✅ YYYY-MM-DD" format. Daily notes use the core Daily notes
settings (.obsidian/daily-notes.json) and are created from its template.
"""
import datetime
import json
import os
import re
import sys

TASK_RE = re.compile(r"^(\s*[-*+] \[)([ xX/])(\]\s+)(.*)$")
BLANK_TASK_RE = re.compile(r"^\s*[-*+] \[ \]\s*$")
DUE_RE = re.compile(r"📅\s*(\d{4}-\d{2}-\d{2})")
DONE_RE = re.compile(r"\s*✅\s*(\d{4}-\d{2}-\d{2})")
BLOCK_ID_RE = re.compile(r"(\s\^[\w-]+)$")
PRIORITIES = {"🔺": 0, "⏫": 1, "🔼": 2, "🔽": 4, "⏬": 5}  # none = 3
# Tasks plugin metadata: emoji followed by its value
META_RE = re.compile(
    r"\s*(?:[📅⏳🛫➕✅❌]️?\s*\d{4}-\d{2}-\d{2}"
    r"|🔁️?[^📅⏳🛫➕✅❌🆔⛔🔺⏫🔼🔽⏬]*"
    r"|🆔\s*\S+|⛔\s*[\w,\s-]+|[🔺⏫🔼🔽⏬]️?)"
)
SKIP_DIRS = {".obsidian", ".git", ".stfolder", ".trash", "Templates"}

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


# ---------- helpers ----------

def read_lines(path):
    with open(path, encoding="utf-8") as f:
        return f.read().split("\n")


def write_lines(path, lines):
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))


def clean(text):
    text = META_RE.sub("", text)
    text = re.sub(r"\[\[([^\]|]+)\|([^\]]+)\]\]", r"\2", text)  # [[a|b]] -> b
    text = re.sub(r"\[\[([^\]]+)\]\]", r"\1", text)  # [[a]] -> a
    text = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", text)  # [a](url) -> a
    text = re.sub(r"(\*\*|__|~~|==|`)", "", text)
    text = re.sub(r"\^[\w-]+\s*$", "", text)  # block ids
    return " ".join(text.split())


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


def daily_note_path(vault, dt):
    folder, fmt, _ = daily_settings(vault)
    return os.path.join(vault, folder, moment_format(dt, fmt) + ".md")


def from_template(vault, dt, title):
    template = daily_settings(vault)[2]
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


def open_daily_note(vault, dt):
    """Return (path, lines) of the daily note for dt, created from the template if missing."""
    path = daily_note_path(vault, dt)
    if os.path.exists(path):
        return path, read_lines(path)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    title = os.path.splitext(os.path.basename(path))[0]
    return path, from_template(vault, dt, title).split("\n")


def ensure_trailing_newline(lines):
    if not lines or lines[-1] != "":
        lines.append("")
    return lines


# ---------- commands ----------

def cmd_list(vault):
    today = datetime.date.today().isoformat()
    out = {"today": today, "vault": vault}
    if not os.path.isdir(vault):
        out.update(error="Vault not found: " + vault, tasks=[])
        return out
    daily = os.path.abspath(daily_note_path(vault, datetime.datetime.now()))
    tasks = []
    for root, dirs, files in os.walk(vault):
        dirs[:] = sorted(d for d in dirs if d not in SKIP_DIRS)
        for name in sorted(files):
            if not name.endswith(".md"):
                continue
            path = os.path.join(root, name)
            try:
                lines = read_lines(path)
            except (OSError, UnicodeDecodeError):
                continue
            for lineno, line in enumerate(lines, 1):
                m = TASK_RE.match(line)
                if not m:
                    continue
                raw = m.group(4)
                text = clean(raw)
                if not text:
                    continue
                done = m.group(2) in "xX"
                done_date = DONE_RE.search(raw)
                # Done tasks only show if they were done today
                if done and not ((done_date and done_date.group(1) == today)
                                 or os.path.abspath(path) == daily):
                    continue
                due = DUE_RE.search(raw)
                tasks.append({
                    "text": text,
                    "done": done,
                    "due": due.group(1) if due else "",
                    "priority": next((p for e, p in PRIORITIES.items() if e in raw), 3),
                    "recurring": "🔁" in raw,
                    "file": path,
                    "note": os.path.splitext(name)[0],
                    "line": lineno,
                    "raw": line,
                })
    tasks.sort(key=lambda t: (t["done"], t["due"] or "9999-99-99", t["priority"]))
    out["tasks"] = tasks
    return out


def cmd_toggle(vault, path, lineno, raw):
    lines = read_lines(path)
    idx = int(lineno) - 1
    if not (0 <= idx < len(lines) and lines[idx] == raw):
        # The note changed since the list was read; find the line again
        matches = [i for i, l in enumerate(lines) if l == raw]
        if not matches:
            sys.exit("Task changed in Obsidian; reload and try again")
        idx = matches[0]
    m = TASK_RE.match(lines[idx])
    if not m:
        sys.exit("Not a task line")
    prefix, status, sep, body = m.groups()
    if status in "xX":
        body = DONE_RE.sub("", body)
        status = " "
    else:
        status = "x"
        stamp = " ✅ " + datetime.date.today().isoformat()
        block = BLOCK_ID_RE.search(body)
        body = body[:block.start()] + stamp + block.group(1) if block else body.rstrip() + stamp
    lines[idx] = prefix + status + sep + body
    write_lines(path, lines)


def cmd_add(vault, text):
    text = " ".join(text.split())
    if not text:
        return
    path, lines = open_daily_note(vault, datetime.datetime.now())
    entry = "- [ ] " + text
    blank = next((i for i, l in enumerate(lines) if BLANK_TASK_RE.match(l)), None)
    if blank is not None:
        # Fill the first empty "- [ ]" slot (e.g. the template's Top 3)
        lines[blank] = entry
    else:
        first = next((i for i, l in enumerate(lines) if TASK_RE.match(l)), None)
        if first is None:
            while lines and lines[-1] == "":
                lines.pop()
            lines.append(entry)
        else:
            # After the last task of the first block of tasks
            end = first
            while end + 1 < len(lines) and TASK_RE.match(lines[end + 1]):
                end += 1
            lines.insert(end + 1, entry)
    write_lines(path, ensure_trailing_newline(lines))
    print(path)


def cmd_log(vault, start, end, minutes, task=""):
    start = datetime.datetime.fromtimestamp(float(start))
    end = datetime.datetime.fromtimestamp(float(end))
    task = " ".join(task.split())
    path, lines = open_daily_note(vault, end)
    while lines and lines[-1] == "":
        lines.pop()
    entry = "- %s–%s Pomodoro (%d min)%s" % (
        start.strftime("%H:%M"), end.strftime("%H:%M"), int(minutes), " · " + task if task else "")
    head = next((i for i, l in enumerate(lines) if LOG_HEADING_RE.match(l)), None)
    if head is None:
        if lines and lines[-1].strip():
            lines.append("")
        lines += [LOG_HEADING, entry]
    else:
        stop = next((i for i in range(head + 1, len(lines)) if HEADING_RE.match(lines[i])), len(lines))
        pos = head + 1
        for i in range(head + 1, stop):  # after the section's last non-blank line
            if lines[i].strip():
                pos = i + 1
        lines.insert(pos, entry)
    write_lines(path, ensure_trailing_newline(lines))
    print(path)


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    cmd, vault, args = sys.argv[1], os.path.expanduser(sys.argv[2]), sys.argv[3:]
    if cmd == "list":
        print(json.dumps(cmd_list(vault), ensure_ascii=False))
    elif cmd == "toggle":
        cmd_toggle(vault, *args)
    elif cmd == "add":
        cmd_add(vault, *args)
    elif cmd == "log":
        cmd_log(vault, *args)
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
