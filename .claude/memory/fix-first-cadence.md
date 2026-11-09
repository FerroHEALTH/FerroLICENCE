---
name: fix-first-cadence
description: An issue filed while working a unit is fixed before the next unit starts; filing is the record, never permission to move on; tests are never weakened to pass (family rule)
metadata:
  type: feedback
---

An issue found while working a unit (a finding, a guard gap, an en-route defect) is filed in the current milestone and fixed before the next unit starts. Tractable findings are fixed in the same branch; separable work becomes a linked issue closed before the work moves on. A test is never weakened, skipped or deleted to make a build pass, and a guard that objects is fixed at the cause.

**Why:** the standing rule of every FerroHEALTH repository's issue workflow; a filed-and-forgotten finding is how defects ship.

**How to apply:** see [[one-milestone-at-a-time]]. Never write "deferred" or "out of scope for now"; the tracker is the scope.
