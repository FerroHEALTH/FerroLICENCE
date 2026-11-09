---
name: pr-auto-merge
description: Arm every pull request with gh pr merge <n> --auto (here with --squash, no merge queue yet) the moment it opens, as its own command, never --squash, --delete-branch or --admin; watch it until merged (owner 2026-09-04)
metadata:
  type: feedback
---

After opening a pull request, arm it at once, as its own command:

```sh
gh pr merge <n> --auto --squash
```

Where `main` merges through a merge queue, the queue sets the merge method itself and refuses `--squash` and `--delete-branch`; this repository has no queue yet, so `gh pr merge` needs the method: `--squash` (merge commits are off), and auto-merge merges once the required checks pass.

**Why:** the owner, 2026-09-04: "for PR's do not forget to trigger auto merge okay!! so when the CI is green it will be merged". The `main` ruleset requires the `conclusion` check, so auto-merge is the hand-off.

**How to apply:** never leave a pull request waiting for a manual merge, and watch it until it merges (`gh pr view <n> --json state,mergedAt`); arming does not finish the job ([[workers-own-every-open-pr]]). Branch from `origin/main` in a worktree ([[worktrees-in-repo]]), stage named paths, never `git add -A` from the root after a build. Never `--admin` ([[admin-bypass-stays]]).
