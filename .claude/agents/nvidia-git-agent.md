---
name: nvidia-git-agent
description: NVIDIA-target documentation for the git-agent push step. The CI workflow in `.github/workflows/build-and-security.yml` is the only writer and computes the next chain step itself — the model is not used in this step. This file documents the rules the workflow enforces for the `feature/nvidia-git-agent_<N>_<TIMESTAMP>` chain.
---

# NVIDIA Git Agent — `feature/nvidia-git-agent` Chain Step (workflow-computed, no model)

You are documenting the **git-agent push step** that lives inside `.github/workflows/build-and-security.yml`. The workflow has already done the heavy lifting (compiled the project, run the scanner, applied remediation patches, verified the build is green). The push step itself is **model-free**: it computes the next chain step's name, parent, timestamp, and commit message from local state, then performs `git push` directly.

This file is **documentation only**. The workflow does not POST to NVIDIA for this step.

## Branch family

The chain steps created by this workflow are:

```
feature/nvidia-git-agent_<N>_<TIMESTAMP>
```

- `<N>` is a 1-based push counter scoped to this branch's chain only.
- `<TIMESTAMP>` is the workflow-computed push time in `YYYY-MM-DD_HH-MM-SS` form (`date +%Y-%m-%d_%H-%M-%S`). Never the literal `time_of_push`.
- The development branch `feature/nvidia-git-agent` is the **bootstrap parent** of push #1.

## Counter rule

```
MAX_N = max(N over all remote+local refs matching `feature/nvidia-git-agent_[0-9]+_*`)
NEW_N = MAX_N + 1
```

Sources (both, not just one):

```bash
git ls-remote --heads origin 'feature/nvidia-git-agent_*'
git branch --list 'feature/nvidia-git-agent_*'
```

The legacy `feature/safe-backup_*` chain is **deliberately ignored** by this counter. Those branches are historical and remain on origin untouched. They are not the parent of any new chain step.

## Chain-from-latest rule

```
feature/nvidia-git-agent                                ← bootstrap (development branch)
   └─ feature/nvidia-git-agent_1_<ts1>                  ← push #1
         └─ feature/nvidia-git-agent_2_<ts2>            ← push #2
               └─ feature/nvidia-git-agent_3_<ts3>      ← push #3
                     └─ ...
```

- The **parent** of push #N is the existing `feature/nvidia-git-agent_<MAX_N>_<its-timestamp>` with the largest N (combined remote + local).
- If no `feature/nvidia-git-agent_<N>_*` ref exists yet, **N = 1** and **parent = `feature/nvidia-git-agent`** (the development branch itself).
- After the push, the runner checks back out to the parent so subsequent runs start from the right tip.

## Hard rules (enforced by the workflow)

1. **Branch format:** `^feature/nvidia-git-agent_[0-9]+_[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}-[0-9]{2}$`
2. **No literal `time_of_push`:** the workflow rejects the timestamp if it contains that substring.
3. **No legacy-family branches:** the workflow never creates `feature/safe-backup_*` chain steps anymore.
4. **Build gate A:** `mvn -B -q compile test-compile` must pass on the new branch before `git push`. On failure the workflow deletes the new branch and aborts.
5. **Reports stay on the development branch:** after the push, `SECURITY_ASSESSMENT_REPORT.md` and `SECURE_REMEDIATION_REPORT.md` are committed back to `feature/nvidia-git-agent` (the trigger branch), not to the chain step. The chain-step branch is rejected as a target.

## Commit message shape

```
NVIDIA git-agent push #<N> — automated remediation

- <bullet 1: one line per Applied finding or per file group>
- <bullet 2: ...>

Build status: Build verified: mvn compile test-compile passed
Source: SECURITY_ASSESSMENT_REPORT.md + SECURE_REMEDIATION_REPORT.md
Parent branch: <PARENT>
Manual merge target: feature/nvidia-git-agent (then main, human review required)

Co-Authored-By: github-actions[bot] <41898282+github-actions[bot]@users.noreply.github.com>
```

## Workflow trigger

The workflow fires on:

- `push` to `feature/nvidia-git-agent`
- `pull_request` targeting `feature/nvidia-git-agent`
- `workflow_dispatch` (manual run from the Actions tab)

It does **not** fire on pushes to `feature/safe-backup_*`, `feature/nvidia-git-agent_<N>_<TS>` chain steps, or any other branch.

## Why the model is not in this step

Originally the NVIDIA model was asked to compute the next chain step and emit a JSON line. That had two failure modes: (a) the model could emit a non-conforming branch name, and (b) the JSON parsing could fail and lose the push entirely. The workflow now does the computation locally and acts as the only writer, so a model error in this step is impossible.

## What is unchanged from the old agent

- The scan (`nvidia-scan`) and remediation (`nvidia-remediate`) jobs **still** call NVIDIA via `integrate.api.nvidia.com`. They are read-only / patch-emitting — they never push.
- The `nvidia-vulnerability-scanner.md` and `nvidia-remediation-agent.md` specs are unchanged.

## What is new vs. the old agent

- Push branch family: was `feature/safe-backup_<N>_<TS>`, now `feature/nvidia-git-agent_<N>_<TS>`.
- Bootstrap parent: was `feature/safe-backup`, now `feature/nvidia-git-agent` (the development branch).
- Counter scope: was `feature/safe-backup_*`, now `feature/nvidia-git-agent_*`.
- Subject prefix: was `Safety backup push #`, now `NVIDIA git-agent push #`.

## Legacy `feature/safe-backup_*` chain (do not touch)

The two existing chain steps `feature/safe-backup_1_2026-06-22_15-36-15` and `feature/safe-backup_2_2026-06-22_18-20-39` remain on origin as historical artifacts. They are not deleted, not rebased onto, and not used as parents for new pushes.