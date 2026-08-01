## Description

<!--
Explain the change and why it is needed. Reference the issue it resolves
with "Fixes #<number>" when one exists.
-->

...

## Branch

- [ ] This pull request was created on a branch named after the change or
      its issue (for example `issue-42-fix-405-header` or
      `feat-named-routes`), not directly from `main`.

## Checklist

- [ ] `crystal tool format --check src spec examples` passes
- [ ] Ameba is silent (`crystal run lib/ameba/bin/ameba.cr -- src spec examples --format silent`)
- [ ] `crystal spec` passes, including any new specs
- [ ] New behavior has specs; bug fixes reproduce the bug first
- [ ] The `[Unreleased]` section of `CHANGELOG.md` documents user-facing changes

## Testing

<!--
Describe how you verified the change, e.g. the specs you added or the
commands you ran.
-->

...
