# PR Review Guide

How to review a GitHub pull request with a fixed rubric and a consistent comment format. Prefer `/pr-review <PR>` (project skill at [`.claude/skills/pr-review/`](../../.claude/skills/pr-review/)); use this guide as the equivalent procedure when the skill cannot be invoked (see [AGENTS.md](../../AGENTS.md) step 7). This document is the human-readable source for the shared rubric, methodology, severities, and comment template.

---

## When to run

Run a PR review after the PR exists and CI is green (or at least after the diff is ready for human review):

1. When you reach **Review** in the workflow ([AGENTS.md](../../AGENTS.md) step 7 — after `gh pr create` and CI checks).
2. Again after you address `[critical]` / `[major]` findings and push fixes.

Do **not** merge after review. Report the PR URL and wait for a human merge or explicit authorization.

---

## Why an independent reviewer

Prefer a **fresh-context** reviewer (subagent or a separate session), not the session that wrote the code. Authoring context biases self-review toward “looks fine.” The reviewer should receive only:

- PR metadata, linked issue(s), and the full diff as primary context
- On-demand access to the rest of the repository (to confirm claims and read surrounding code)

If you cannot spawn an independent subagent, still follow the same rubric and format below; call out that the review was not independent if you wrote the change.

---

## Prerequisites

- Inside a git work tree for this repository
- `gh` authenticated to the repo remote (`gh auth status`)
- A PR number or URL (or a branch with an open PR)

If `gh` is not authenticated or you are not in the repo, stop with a clear message.

---

## Procedure

### Step 1 — Resolve the PR

```bash
# From an argument (number or URL):
PR=256   # or full https://github.com/owner/repo/pull/256

# Or infer from the current branch:
PR="$(gh pr view --json number -q .number)"
```

If neither works, stop and ask for the PR number or URL.

### Step 2 — Gather context (deterministic)

Collect **PR metadata**, **linked issue(s)** with full body text, **changed-file list**, and the **complete diff**. Do not post a comment yet.

#### Option A — Project skill bundle script (preferred)

```bash
CTX="$(bash "$(git rev-parse --show-toplevel)/.claude/skills/pr-review/gather_context.sh" "$PR")"
# Read $CTX; it holds metadata, files, linked issues, and the full diff.
```

#### Option B — Portable `gh` commands (no skill script)

Prefer the GitHub **REST API** via `gh api` for issue bodies (same approach as the skill’s bundle script). `gh issue view` can fail on some repos because of GraphQL deprecations around project cards.

```bash
REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
PR_NUM="$(printf '%s' "$PR" | sed -E 's@^.*/pull/([0-9]+).*@\1@; s/^#//; s/[^0-9]//g')"

# PR metadata
gh api "repos/$REPO/pulls/$PR_NUM" --jq \
  '"**Title:** \(.title)\n**Author:** \(.user.login)\n**Base:** \(.base.ref)  ←  **Head:** \(.head.ref)\n**State:** \(.state)\n**Files:** \(.changed_files) (+\(.additions)/-\(.deletions))\n\n**Body:**\n\(.body // "(no PR body)")"'

# Changed files
gh api "repos/$REPO/pulls/$PR_NUM/files" --jq \
  '.[] | "- [\(.status)] \(.filename)  (+\(.additions)/-\(.deletions))"'

# Full diff
gh pr diff "$PR_NUM"

# Linked issues: parse closes/fixes/resolves (and similar) from PR body + commits,
# then fetch each issue body via REST, e.g.:
gh api "repos/$REPO/issues/<N>" --jq \
  '"**\(.title)**  (state: \(.state))\n\n\(.body // "(no issue body)")"'
```

Linked issues are usually referenced in the PR body or commit messages with keywords such as `closes`, `fixes`, `resolves`, `implements`, `references`, or `see` followed by `#N`. If none are found, evaluate correctness against the PR’s own stated intent and note “none detected” in the comment.

If part of the fetch fails, proceed with a partial bundle and note the gap in the review comment.

### Step 3 — Review against the rubric

Evaluate **every** dimension below. Read surrounding code and tests as needed; do **not** limit yourself to the diff.

#### Rubric

1. **Correctness vs. the linked issue** — Does the diff satisfy the issue’s stated goal and acceptance criteria? Note missing cases, wrong behavior, broken or absent tests, and regressions. If there is no linked issue, evaluate against the PR’s stated intent.
2. **Security** — Real issues only for this code: input validation, auth/authz, injection (SQL/command/HTML), secret handling, unsafe deserialization, SSRF, path traversal, resource exhaustion, unsafe dependency use. No security theater.
3. **Modularity** — Are concerns decomposed into sensible, independently reasonable units?
4. **Abstraction** — Right level? Leaky, speculative, or premature abstractions?
5. **Cohesion** — Does each unit do one thing well?
6. **Separation of concerns** — Distinct responsibilities kept apart (e.g. I/O vs. logic, policy vs. mechanism, build vs. runtime)?
7. **Coupling** — Units unnecessarily entangled? Could dependencies point a better direction or be narrower?

#### Methodology

- Verify every finding against the actual code before writing it. Cite `file:line`. If you cannot confirm a concern after reading the code, drop it or mark it explicitly uncertain — do not speculate.
- Distinguish real defects from style preferences. Reserve `[nit]` for pure style.
- Be concrete: each finding states the **problem** and a **specific suggested fix**.
- Prefer fewer, high-confidence findings over a long list of maybes.
- Focus on actionable findings — do **not** include `[praise]` sections.

#### Severity tags

| Tag | Meaning |
|-----|---------|
| `[critical]` | Must fix before merge (correctness break, security hole, data loss risk, etc.) |
| `[major]` | Should fix before merge (significant bug, missing acceptance criterion, serious design flaw) |
| `[minor]` | Worth fixing; may accept with explanation if low risk |
| `[nit]` | Style or preference only |

Design findings also carry a **dimension** tag: `[modularity]`, `[abstraction]`, `[cohesion]`, `[separation of concerns]`, or `[coupling]`.

### Step 4 — Write the comment body

Return **only** this markdown structure (it becomes the PR comment):

```markdown
## 🧭 pr-review — PR #<PR_NUM>

**Linked issue:** #<n> — <title>   *(or: none detected)*
**Scope:** <N files, +a/-d> — <one-line summary of what changed>

### Correctness vs. issue
- [severity] `file:line` — finding. **Fix:** ...
*(or: "No correctness issues found against the issue's criteria.")*

### Security
- [severity] `file:line` — finding. **Fix:** ...
*(or: "No security issues found.")*

### Design — modularity / abstraction / cohesion / separation of concerns / coupling
- [dimension] [severity] `file:line` — finding. **Fix:** ...
*(or: "No notable design issues.")*

### Verdict
<1–3 sentences. One of: ✅ Approve / 🔁 Request changes / 💬 Needs discussion.>
```

**Verdict guidance:**

- **✅ Approve** — No critical/major issues (or only accepted nits/minors).
- **🔁 Request changes** — At least one critical or major finding that should block merge until addressed.
- **💬 Needs discussion** — Ambiguous requirements, trade-offs that need a human decision, or incomplete context (e.g. missing linked issue with unclear intent).

### Step 5 — Post the PR comment

Show the comment body to the user, then post it (posting is the intended action unless the body is empty or the user interrupts):

```bash
BODY="$(mktemp)"
# Write the markdown body into $BODY (editor, heredoc, or Write tool)
gh pr comment "$PR_NUM" --body-file "$BODY"
rm -f "$BODY"
# Also remove any context temp file if you created one
```

Using `--body-file` avoids shell-escaping problems with large multiline markdown.

---

## After the review (author / implementing agent)

Once findings are posted:

1. **Fix or explain** every `[critical]` and `[major]` finding.
2. **Resolve or accept** `[minor]` and `[nit]` findings (fix them, or document why not in the PR thread).
3. Push fixes and **re-run** this review procedure on the same PR.
4. Report the PR URL to the user. **Do not merge** unless explicitly authorized.

---

## Requirements and failure modes

| Situation | Action |
|-----------|--------|
| Not in a git repo / `gh` not authenticated | Stop with a clear message |
| Cannot resolve PR number | Ask the user |
| Diff or issue fetch fails | Proceed with partial context; note the gap in the comment |
| Empty review body | Do not post |
| No linked issue | Evaluate vs. PR intent; write “none detected” under Linked issue |

---

## Reproducibility

Context gathering is scripted (or uses the portable `gh` sequence above). The reviewer follows the fixed rubric and output format so every run produces a consistently structured comment. Judgment is LLM-based; inputs, dimensions, and output schema are not.

---

## Related

- [`.claude/skills/pr-review/`](../../.claude/skills/pr-review/) — project skill (`SKILL.md` + `gather_context.sh`); invoke as `/pr-review`
- [Development Workflow Guide](./development_workflow.md) — full branch → PR → merge flow
- [AGENTS.md](../../AGENTS.md) — project workflow; step 7 points here for review detail
- [Repository Security](../explanation/security.md) — secrets and public-repo commit policy (security dimension)
