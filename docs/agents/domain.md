# Domain Docs

## Layout

This repository uses a single context: root `CONTEXT.md` for domain terminology and `docs/adr/` for architecture decisions. Preserve the existing ADRs.

## Before exploring

Read root `CONTEXT.md`, then the ADRs in `docs/adr/` relevant to the work. If `CONTEXT-MAP.md` is introduced later, follow its pointers to the contexts relevant to the task and their ADRs.

If a context document or ADR directory is absent, proceed silently. Domain-modeling creates domain documents lazily as terminology or decisions are resolved; setup does not create placeholder domain content.

## Vocabulary

Use the glossary's terms in issues, hypotheses, proposals, code and tests. For a missing term, first check whether the repository already has a term; record a real gap for domain-modeling.

## ADR conflicts

When a proposal contradicts an accepted ADR, identify that ADR and explain why the decision should be reopened before implementing the conflicting change.
