# Issue tracker: GitHub

Issues and specs live in `DaisenHo/healthlog-iOS`. Use the `gh` CLI with an explicit `--repo DaisenHo/healthlog-iOS`; REST requests use `repos/DaisenHo/healthlog-iOS/...`. This keeps ticket operations on the personal fork rather than its upstream.

## Conventions

- Create: `gh issue create --repo DaisenHo/healthlog-iOS --title "..." --body-file <file>`.
- Read with labels and discussion: `gh issue view <number> --repo DaisenHo/healthlog-iOS --json number,title,body,state,labels,comments`.
- List: `gh issue list --repo DaisenHo/healthlog-iOS --state open --json number,title,body,labels,comments`, adding label/state filters as needed.
- Comment: `gh issue comment <number> --repo DaisenHo/healthlog-iOS --body-file <file>`.
- Add/remove labels: `gh issue edit <number> --repo DaisenHo/healthlog-iOS --add-label "..."` / `--remove-label "..."`.
- Close: `gh issue close <number> --repo DaisenHo/healthlog-iOS --comment "..."`.

Write multiline bodies to a UTF-8 file and pass `--body-file`. Use synthetic health data in public tickets and attachments.

When a skill says "publish to the issue tracker", create a GitHub issue here. When it says "fetch the relevant ticket", read the issue and comments here.

## Pull requests as a triage surface

**PRs as a request surface: no.**

GitHub shares issue and PR numbers. Resolve a bare number with `gh pr view <number> --repo DaisenHo/healthlog-iOS`, falling back to `gh issue view <number> --repo DaisenHo/healthlog-iOS`. This identifies the object without opting PRs into the triage queue.

## Wayfinding operations

- Map: one issue labelled `wayfinder:map`, holding Notes / Decisions-so-far / Fog.
- Child: a map sub-issue with `wayfinder:research`, `wayfinder:prototype`, `wayfinder:grilling`, or `wayfinder:task`. If sub-issues are unavailable, use a task list in the map and `Part of #<map>` in the child.
- Blocking: use native issue dependencies. Add with `gh api --method POST repos/DaisenHo/healthlog-iOS/issues/<child>/dependencies/blocked_by -F issue_id=<blocker-db-id>`. Obtain the database id from `gh api repos/DaisenHo/healthlog-iOS/issues/<blocker-number> --jq .id`. If dependencies are unavailable, use a `Blocked by: #<number>` line. A ticket is unblocked when all blockers close.
- Frontier: consider open children in map order; skip assigned tickets or tickets with open blockers. Native `issue_dependencies_summary.blocked_by` counts open blockers.
- Claim: `gh issue edit <number> --repo DaisenHo/healthlog-iOS --add-assignee @me`.
- Resolve: comment with the answer, close the ticket, and add a gist plus link to the map's Decisions-so-far.
