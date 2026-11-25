# Auditing the first pass

A first, faster model labelled every Dharma Seed retreat with practice
categories, following `GUIDE.md` in this folder. You are the check. Your
reading of each retreat you see is final: it replaces the first pass's.

Read `GUIDE.md` first: the categories, their ids and "How to decide" apply to
you exactly as they did to the first pass. Precision matters more than recall.

## Input

A JSONL file, one retreat per line, with the same fields the first pass saw
(`id`, `name`, `teachers`, `talks`, `talk_titles`, `description`) plus:

- `proposed`: the first pass's categories;
- `proposed_reason`: its stated evidence;
- `why_audited`: `sample` (a random check), `none` (it gave no categories), or
  `four or more`.

## What to check

- **For `none`:** is there really no identifiable practice focus? A retreat
  titled "Spring Retreat" whose talk titles are all guided metta is `metta`.
  A sangha-night series of Dharma talks on assorted topics stays none.
- **For `four or more`:** which of these are a substantial focus, and which
  are mentions in passing? Keep only what is earned.
- **For `sample`:** read it fresh, then compare. Fix wrong labels and add a
  clearly missing one; do not churn borderline calls (if the proposal is a
  reasonable reading, keep it).

## Output

A JSONL file with exactly one line per input retreat, same order, nothing
else:

{"id": 1234, "categories": ["metta"], "verdict": "changed", "reason": "Talk titles are all guided metta; first pass missed it."}

`verdict` is `agree` when `categories` equals `proposed` (as a set), else
`changed`. `reason` is one sentence, under 25 words.
