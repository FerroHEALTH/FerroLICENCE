# 04. Check a licence, attest a database

For everyone with access to the register's repository. No YubiKey needed. Both work
offline against the last register the app read.

## Check a licence file

1. Open **Check a File** in the sidebar.
2. Drop the file from Mail or Finder on the dashed area, paste its text
   (⌘V), or click **Open File…** in the toolbar.

The banner answers first, in words: "Valid on 24 Oct 2026, until 31 Dec
2099.", "Not valid on 24 Oct 2026. It ended on 30 Sep 2026, 24 days
before.", "Signed by a retired key", "The file was changed after it was
signed."

Under it, **This Licence**:

- **Customer** and **Valid**: what the file says.
- **Genuine**: signed by one of our keys, and whether it is in the
  register. A genuine signature whose id is not in the register is a
  forgery, or the app has not synced yet (⌘R).
- **In FerroEHR**: whether the server runs under it, or ignores it and runs
  on the free licence.
- **Checks**: how many of FerroEHR's nine checks passed. Click the row to
  see each one in order, with the one that failed (`../design.md` §5).

A revocation shows in **Genuine**, with the day it took effect.

## Attest Data: whose licence made this data

1. Open **Attest Data** in the sidebar.
2. Drop or paste anything that holds identifiers: a `pg_dump` excerpt, a
   log, the JSON of a few `GET …/composition/…` responses, a CSV export.
   **Open File…** works too. Every UUID in it is read.

The banner names the licence the identifiers were made under, or says that
none matches. Under it, **Result**:

- **Evidence**: how many identifiers carry the licence's mark.
- **By chance**: how unlikely that is by accident.
- **Made**: the first and last day those identifiers were made.
- **Note**: how many were made after the licence ended, or after its
  revocation, when there are any.

Twenty or more identifiers settle it; the app calls a licence identified at
p ≤ 10⁻⁹ (`../design.md` §8). **Copy Report** in the toolbar puts the full
numbers on the clipboard, for a letter or a case file.

Read the register entry and the agreement before doing anything else. The
free licence's mark on a production database may be non-commercial use,
which BUSL permits. It is a reason to ask; on its own it proves nothing
(`../design.md` §10).

## Sync

The register is read from GitHub at launch, when the window comes to the
front, every five minutes, after every change the app records, and on
View › Sync Now (⌘R). The toolbar's sync symbol opens a popover with the
commit read, anything still recording, the offline copy and the next sync.
Without a connection the window's subtitle says when the offline copy was
saved.
