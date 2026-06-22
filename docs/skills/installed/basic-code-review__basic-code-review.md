<!--
Copied skill source for documentation.
Original path: /Users/najongseong/.codex/skills/basic-code-review/SKILL.md
Source group: installed
Skill name: basic-code-review
Original relative directory: basic-code-review
-->

---
name: basic-code-review
description: "Perform concise, consistent reviews for small code changes. Use when the user asks for a quick code or PR review (for example: 코드 리뷰해줘, 이 PR 어때?, 변경점 검토해줘) and the focus is bug risk, readability, maintainability, and missing tests in a limited diff."
---

# Basic Code Review

Review small diffs quickly and consistently.

## Workflow

1. Read change context from `git status`, `git diff`, and any provided commit or PR description.
2. Prioritize findings by severity in this order: correctness, regression risk, maintainability/readability, style.
3. Report only actionable findings and include precise file and line references.
4. Explain impact and fix direction for each finding; add a short code example only when it removes ambiguity.
5. State explicitly when no findings are present, then mention residual risks (for example, missing tests).

## Output Format

1. Findings (highest severity first)
2. Open questions or assumptions
3. Brief change summary (optional)

Use priority labels when relevant: `[P0]`, `[P1]`, `[P2]`, `[P3]`.

## Review Quality Rules

- Tie every comment to concrete behavior, risk, or maintenance cost.
- Avoid vague suggestions without a clear reason or next step.
- Do not block on style-only nits unless they reduce readability or violate local conventions.
- Call out missing or weak tests when behavior changes.
