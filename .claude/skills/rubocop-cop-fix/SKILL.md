---
name: rubocop-cop-fix
description: Fix a RuboCop cop crash or bad autocorrect and prepare the upstream change — MRE, branch, spec, changelog, commit. Use for a rubocop-nightly fuzzer reproduction, an "An error occurred while <Cop> cop was inspecting" report, or a Parser::ClobberingError.
---

# Fixing a RuboCop cop bug

## 1. Reproduce and minimise

Always end the work by printing an MRE in this format, verified by running it:

```bash
bundle exec rubocop --stdin /dev/stdin -a -d --config <(cat <<'YAML'
AllCops:
  DisabledByDefault: true
  SuggestExtensions: false
Cop/Name:
  Enabled: true
YAML
) <<'RUBY'
<source>
RUBY
```

- `-d` prints the backtrace — quote only the cop's own frames, not all 90 lines.
- `-a` never applies a `Safe: false` cop. If nothing reproduces, try `--autocorrect-all`
  before concluding the shape is wrong.
- Add `AllCops/TargetRubyVersion` only when the syntax needs it (`3.4` for `foo:` value
  omission), otherwise the parser defaults to 2.7 and you get `Lint/Syntax`, not the bug.
- Heredocs, never `echo`/`printf` — these bugs are positional, and reflowing hides them.
- Minimise by deletion, not by guessing: drop each config key, pair, and character and
  re-run. Identifier *lengths* are often load-bearing — sweep them for the threshold.
  Use `aa`/`bbb`; never keep names from the corpus file.
- Under `-a` the crash may only appear on stderr while the run still prints correct
  output and a plausible offence count. Grep for `Error`, don't trust the summary.
- If the cop has a mirror path (`EnforcedStyle` A vs B, `[]` vs `fetch`), test both —
  the second is usually broken the same way.

## 2. Fix

- Branch `fix-an-error-for-<cop-slug>-cop` (`Style/HashLookupMethod` →
  `fix-an-error-for-style-hash-lookup-method-cop`); add `-<detail>` if taken.
- Prefer narrowing the guard the cop already has over hardening the corrector.
- Add specs to the cop's existing spec file. Confirm they **fail on master** — copy them
  into a `git worktree` at master and run there. A spec that passes both ways is not a
  regression test.
- `bundle exec rspec spec/rubocop/cop/<dept>/<cop>_spec.rb` and `bundle exec rubocop`
  must both be clean.

## 3. Changelog

```bash
.claude/skills/rubocop-cop-fix/next-pr-number.sh   # → e.g. 15625
```

`changelog/fix_an_error_for_<snake_description>_<YYYYMMDDHHMMSS>.md`, exactly one line:

```
* [#N](https://github.com/rubocop/rubocop/pull/N): Fix an error for `Cop/Name` when <condition>. ([@viralpraxis][])
```

`spec/project_spec.rb` enforces the numeric link, so a placeholder must still be a
number — say so when reporting. A separate trigger gets its own entry; never widen an
existing one.

## 4. Commit

Subject `Fix an error for \`Cop/Name\` cop`, body `An MRE:` followed by the shell block.

## Repo hygiene

Never `git stash` here — check `git branch --show-current` and `git status` first, since
branches may have moved between turns. Assert that scripted edits matched before writing.
