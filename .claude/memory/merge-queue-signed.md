---
name: merge-queue-signed
description: main takes only signed commits through pull requests; arm with gh pr merge --auto, fix a conflict by a local signed merge, never update-branch --rebase or --admin; no commit-message line may start with "-" or a git header word (FerroEHR #5233, #5245, 2026-11-09)
metadata:
  type: feedback
---

The `main` ruleset requires signed commits and a pull request. This repository has no merge queue yet (ruleset read on 2026-11-09), so auto-merge merges a pull request once its required checks pass; the family repositories with a queue gate it on `conclusion`.

**Why:** a server-side rebase (`gh pr update-branch --rebase`) drops the author's signature and the ruleset then refuses the branch; the queue tests pull requests on top of `main`, so a branch never has to be brought up to date by hand, and several land per CI run.

**How to apply:** arm a pull request with `gh pr merge <n> --auto` (in a repository with a merge queue, the queue sets the method and refuses `--squash` and `--delete-branch`). Fix a conflicting branch with a local merge of `origin/main`, signed by `commit.gpgsign`, and a plain push; no force-push. Dependabot branches get `@dependabot rebase`. Never `--admin` ([[admin-bypass-stays]]).

**Commit-message lines (2026-11-09):** no line of a commit message may start with `-` or with a git header word (`tree`, `parent`, `author`, `committer`, `gpgsig`). A merge queue's squash commit then fails its signature check and the queue removes the PR with `branch_protection_failure` after a green run (FerroEHR #5233 and #5245). Write the body as prose sentences, not a dashed list.
