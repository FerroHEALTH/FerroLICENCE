#!/usr/bin/env bash
# scripts/release/notes-html.sh vX.Y.Z
#
# The CHANGELOG.md section for the version as plain HTML, for the update
# window's release notes: ### headings and - items, inline code and bold.

set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"

# shellcheck disable=SC2016 # the program is Python, not shell
bash "$here/notes.sh" "${1:?usage: notes-html.sh vX.Y.Z}" | python3 -I -c '
import html, re, sys
out, item, inlist = [], None, False
def inline(t):
    t = html.escape(t)
    t = re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", t)
    t = re.sub(r"`(.+?)`", r"<code>\1</code>", t)
    return re.sub(r"\[(.+?)\]\((.+?)\)", r"\1", t)
def flush():
    global item
    if item is not None:
        out.append("<li>" + inline(item) + "</li>")
        item = None
for line in sys.stdin.read().splitlines():
    if line.startswith("### "):
        flush()
        if inlist: out.append("</ul>"); inlist = False
        out.append("<h3>" + inline(line[4:]) + "</h3>")
    elif line.startswith("- "):
        flush()
        if not inlist: out.append("<ul>"); inlist = True
        item = line[2:]
    elif line.strip() and item is not None:
        item += " " + line.strip()
flush()
if inlist: out.append("</ul>")
print("\n".join(out))
'
