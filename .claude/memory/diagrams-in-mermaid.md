---
name: diagrams-in-mermaid
description: Every diagram in a markdown file is a ```mermaid block, never ASCII or box-drawing art; owner request 2026-10-07
metadata:
  type: feedback
---

Draw every diagram in markdown as a fenced `mermaid` block (flowchart, sequenceDiagram, ...), never as ASCII or box-drawing characters. The one existing drawing (`docs/design.md` §2) was converted on 2026-10-07.

**Why:** the owner asked for it explicitly ("if you make any drawings do that in mermaid, update all markdown files"); GitHub renders Mermaid, and it stays editable.

**How to apply:** any new or changed diagram in this repository's docs, manuals or PR bodies uses Mermaid; plain arrows in prose (menu paths like "Settings → General") are not diagrams and stay as they are.
