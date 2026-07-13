---
name: pr-review
description: Review a GitHub pull request for correctness against its linked issue, security, and design quality (modularity, abstraction, cohesion, separation of concerns, coupling). Gathers PR + issue + diff deterministically, runs the review in an INDEPENDENT subagent context with on-demand repository access, and posts the findings as a PR comment via the gh CLI. Invoke as /pr-review <PR-number-or-URL>.
allowed-tools: Bash, Agent, Read, Write, Grep, Glob
---

# pr-review

Review a GitHub PR across a fixed rubric and post the findings as a PR comment.

This skill lives in the **ymatch project** at `.claude/skills/pr-review/` (same pattern as `dev-up`). The human-readable how-to and shared rubric source is [docs/how_to/pr_review.md](../../../docs/how_to/pr_review.md).

## Invocation

`/pr-review <PR-number-or-URL>` — e.g. `/pr-review 256` or `/pr-review https://github.com/owner/repo/pull/256`.

If no argument is given, infer the PR from the current branch (`gh pr view --json number -q .number`); if that fails, stop and ask.

## Why an independent subagent

The review is performed by a **fresh-context subagent** (Agent tool), not the main session. The main session may have written the code under review, which biases self-review toward "looks fine." The subagent receives only the PR + issue + diff as context (plus on-demand repo access), so its judgment is independent of how the code came to be.

## Procedure

### Step 1 — Gather context (deterministic)

Run the bundle script that lives next to this SKILL.md. It fetches PR metadata, the linked issue(s), and the full diff via the GitHub REST API and writes them to a temp file, printing the path.

```bash
CTX="$(bash "$(git rev-parse --show-toplevel)/.claude/skills/pr-review/gather_context.sh" <PR>")"
```

`<PR>` is the number or URL passed by the user. Read the bundle so you can summarize scope to the user and fill the subagent prompt. Do NOT post anything yet.

Works from any worktree: the script path is resolved from the repo root via `git rev-parse --show-toplevel`.

### Step 2 — Spawn the independent reviewer (Agent tool)

Call the **Agent** tool with `subagent_type: "general-purpose"` and the prompt below (substitute the real `<PR_NUM>`, `<REPO_ROOT>`, and `<CTX_PATH>`). The subagent inherits the repo as its working directory, so it can read any file on demand.

Prompt template:

> You are a senior code reviewer. Review PR **#<PR_NUM>** in the repository at `<REPO_ROOT>`.
>
> **Inputs**
> - Read the context bundle at `<CTX_PATH>`. It contains: PR metadata, the changed-file list, any linked issue(s) with full body text, and the complete diff. Start there.
> - You have on-demand access to the repository at `<REPO_ROOT>` (Read/Grep/Glob/Bash). Use it to read surrounding code, confirm claims, and check tests. Do NOT limit yourself to the diff — read whatever you need to be accurate.
>
> **Rubric — evaluate every dimension**
> 1. **Correctness vs. the linked issue** — Does the diff actually satisfy the issue's stated goal and acceptance criteria? Note missing cases, wrong behavior, broken or absent tests, and regressions. If there is no linked issue, evaluate correctness against the PR's own stated intent.
> 2. **Security** — Real issues only for this code: input validation, auth/authz, injection (SQL/command/HTML), secret handling, unsafe deserialization, SSRF, path traversal, resource exhaustion, unsafe dependency use. No theater.
> 3. **Modularity** — Are concerns decomposed into sensible, independently-reasonable units?
> 4. **Abstraction** — Right level? Leaky, speculative, or premature abstractions?
> 5. **Cohesion** — Does each unit do one thing well?
> 6. **Separation of concerns** — Distinct responsibilities kept apart (e.g. I/O vs. logic, policy vs. mechanism, build vs. runtime)?
> 7. **Coupling** — Units unnecessarily entangled? Could dependencies point a better direction or be narrower?
>
> **Methodology**
> - Verify every finding against the actual code before writing it. Cite `file:line`. If you cannot confirm a concern after reading the code, drop it or mark it explicitly uncertain — do not speculate.
> - Distinguish real defects from style preferences. Reserve `[nit]` for pure style. Focus the output on actionable findings — do not include `[praise]` sections.
> - Be concrete: each finding states the problem AND a specific suggested fix.
> - Prefer fewer, high-confidence findings over a long list of maybes.
>
> **Output — return ONLY this markdown (it will be posted as the PR comment)**
>
> ```
> ## 🧭 pr-review — PR #<PR_NUM>
>
> **Linked issue:** #<n> — <title>   *(or: none detected)*
> **Scope:** <N files, +a/-d> — <one-line summary of what changed>
>
> ### Correctness vs. issue
> - [severity] `file:line` — finding. **Fix:** ...
> *(or: "No correctness issues found against the issue's criteria.")*
>
> ### Security
> - [severity] `file:line` — finding. **Fix:** ...
> *(or: "No security issues found.")*
>
> ### Design — modularity / abstraction / cohesion / separation of concerns / coupling
> - [dimension] [severity] `file:line` — finding. **Fix:** ...
> *(or: "No notable design issues.")*
>
> ### Verdict
> <1–3 sentences. One of: ✅ Approve / 🔁 Request changes / 💬 Needs discussion.>
> ```
>
> Severity tags: `[critical]` `[major]` `[minor]` `[nit]`.
>
> Do not post anything. Do not run gh. Return the markdown comment body and nothing else.

Take the subagent's returned text as the comment body.

### Step 3 — Post the PR comment

Write the comment body to a temp file (avoids shell-escaping issues with large multiline markdown) and post it:

```bash
BODY="$(mktemp)"
# <write the subagent's markdown to $BODY — e.g. via a heredoc or the Write tool>
gh pr comment <PR> --body-file "$BODY"
rm -f "$BODY" "$CTX"
```

Show the comment body to the user before posting. Posting is the designed action of this skill, so proceed unless the body is empty or the user interrupts.

## Requirements & failure modes

- Must be run inside a git work tree with `gh` authenticated to the repo's remote. If `gh` is not authed or not in a repo, stop with a clear message.
- If the bundle script fails to fetch the diff or issue, it still emits a partial bundle with inline `(failed to fetch …)` notes — proceed with the review and note the gap in the comment.
- The bundle and comment temp files are cleaned up after posting.

## Reproducibility

Context gathering is fully scripted (`gather_context.sh`, REST API) and the reviewer follows the fixed rubric and output format above, so `/pr-review <PR>` produces a consistently-structured review every time. The reviewer's *judgment* is LLM-based, but its inputs, dimensions, and output schema are deterministic.

## Related

- [docs/how_to/pr_review.md](../../../docs/how_to/pr_review.md) — full how-to (same rubric; portable procedure without invoking the skill)
- [AGENTS.md](../../../AGENTS.md) step 7 — when to run review in the development workflow
