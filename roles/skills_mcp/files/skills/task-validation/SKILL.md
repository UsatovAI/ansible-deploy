---
name: task-validation
description: Verify that a completed piece of work actually satisfies the original task request, as a check distinct from code review. Use when asked to validate, verify, sign off on, or QA whether an implementation is "done" or "ok for the task" — checking requirement/acceptance-criteria coverage and behavior under active testing, not style or maintainability (use code-review-skill for that instead).
---

# Task Validation

Answers one question only: **does this implementation actually do what was asked?**
This is the Evaluator half of a QA role — deliberately separate from code review (which asks "is
this code well-written?"). Run both when reviewing finished work; they catch different things and
one agent grading both blurs the skepticism that makes either one useful.

Distilled from Anthropic's write-up on harness design for long-running agents
([engineering/harness-design-long-running-apps](https://www.anthropic.com/engineering/harness-design-long-running-apps)):
separating a Generator from an Evaluator matters because "agents reliably skew positive when
grading their own work." Run this skill as, or from, a context that did not write the code —
minimum a fresh read with no attachment to the implementation choices made.

## When to use vs. code-review-skill

| Question | Skill |
|---|---|
| Does this satisfy the task that was asked? | **task-validation** (this skill) |
| Is this code well-written, secure, maintainable? | `code-review-skill` |

They're complementary, not redundant — code can be beautifully written and still not do the job,
or do the job while being a mess. Run task-validation first: no point reviewing code style for a
feature that doesn't work.

## Process

### 1. Recover the original ask

Find the actual task/request text (issue, prompt, spec, ticket) — not the implementer's summary
of it. Implementers unconsciously reframe scope to match what they built. If only a summary is
available, treat it with suspicion and look for the original wording.

### 2. Turn it into concrete, testable criteria

Vague goals ("make login better") don't yield a pass/fail. Rewrite the ask as a checklist of
specific, checkable claims before looking at the implementation:

- Feature completeness: every explicit requirement in the ask, listed as a separate line item
- Explicit non-goals or constraints mentioned in the ask (e.g. "don't change the API shape")
- Edge cases the ask implies even if unstated (empty input, auth failure, concurrent use)
- Bug-freeing: no regressions in adjacent behavior the change touches

If the ask had a negotiated "definition of done" (a sprint contract, acceptance criteria in a
ticket), use that verbatim instead of re-deriving it — it's authoritative.

### 3. Actively exercise the change — don't just read it

Reading a diff and reasoning "this looks like it would work" is exactly the failure mode this
skill exists to avoid. For each criterion from step 2, verify it by doing one of, in order of
preference:

1. Run the actual test suite covering the change; if none exists for a criterion, that's itself a
   finding.
2. Drive the change directly — run the CLI command, hit the endpoint, load the page, call the
   function with real inputs — the same way a user or caller would.
3. Only fall back to static read-through when neither is possible (e.g. infra you can't spin up),
   and say so explicitly in the verdict rather than silently downgrading rigor.

Prefer tools that interact with a live system (test runners, curl, a browser, a REPL) over
inference from source alone.

### 4. Calibrate skepticism

Default to skeptical, not lenient — lenient evaluators are the most common failure mode of this
kind of check. Concretely:

- An unverified criterion is not a pass. Mark it unverified, don't assume success.
- "Should work" is not evidence. Only a criterion you actually exercised counts as verified.
- Partial completion is not done. If 4 of 5 requirements are met, the verdict is FAIL with one
  item outstanding, not "mostly done."

### 5. Report a verdict, not a narrative

```markdown
## Task Validation: <task summary>

**Verdict:** PASS | FAIL | PASS WITH GAPS

### Criteria
- [x] <criterion> — verified by <test run / manual exercise, with the actual output>
- [ ] <criterion> — NOT MET: <what happened instead>
- [~] <criterion> — unverifiable in this environment: <why, and what would verify it>

### Regressions checked
<adjacent behavior exercised to confirm no breakage>
```

A criterion marked `[x]` must cite what was actually run or observed — not a restatement of the
code's intent. If nothing was run, nothing is `[x]`.
