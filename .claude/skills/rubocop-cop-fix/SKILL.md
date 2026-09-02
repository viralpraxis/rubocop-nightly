---
name: rubocop-cop-fix
description: Fix a RuboCop cop crash or bad autocorrect and prepare the upstream change — MRE, branch, spec, changelog, commit. Use for a rubocop-nightly fuzzer reproduction, an "An error occurred while <Cop> cop was inspecting" report, or a Parser::ClobberingError.
---

# Fixing a RuboCop cop bug

## 1. Reproduce and minimise

Always end the work by printing an MRE in this format, verified by running it:

```bash
bundle exec rubocop --debug --stdin /dev/stdin -a --config <(cat <<'YAML'
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

- `--debug` prints the backtrace — quote only the cop's own frames, not all 90 lines.
- `-a` never applies a `Safe: false` cop. If nothing reproduces, try `--autocorrect-all`
  before concluding the shape is wrong.
- Add `AllCops/TargetRubyVersion` only when the syntax needs it (`3.4` for `foo:` value
  omission), otherwise the parser defaults to 2.7 and you get `Lint/Syntax`, not the bug.
- Heredocs, never `echo`/`printf` — these bugs are positional, and reflowing hides them.
- `rubocop-rspec` cops only run on spec-shaped paths, so `--stdin /dev/stdin` silently
  reports no offences. Use `--stdin a_spec.rb`, and add `plugins: - rubocop-rspec`
  to the config.
- Minimise by deletion, not by guessing: drop each config key, pair, and character and
  re-run. Identifier *lengths* are often load-bearing — sweep them for the threshold.
  Once it is not, use the shortest neutral name that still reproduces (`A`, `aa`);
  never keep names from the corpus file.
- Under `-a` the crash may only appear on stderr while the run still prints correct
  output and a plausible offence count. Grep for `Error`, don't trust the summary.
- If the cop has a mirror path (`EnforcedStyle` A vs B, `[]` vs `fetch`), test both —
  the second is usually broken the same way. The same goes for positions within a
  construct — first pair versus later pairs, receiver versus argument. Test the siblings
  rather than reasoning that they are fine; that reasoning is what leaves the follow-up.

## 2. Fix

- Branch `fix-an-error-for-<cop-slug>-cop` (`Style/HashLookupMethod` →
  `fix-an-error-for-style-hash-lookup-method-cop`); add `-<detail>` if taken.
- Prefer narrowing the guard the cop already has over hardening the corrector.
- Write no comments unless asked. Name the predicate so the diff explains itself; the
  changelog and PR description carry the reasoning.
- Add specs to the cop's existing spec file. Confirm they **fail on master** — copy them
  into a `git worktree` at master and run there. A spec that passes both ways is not a
  regression test.
- Check each new spec is not redundant before keeping it. Break the fix in the plausible
  over-broad way and rerun: a spec no mutation makes fail is already covered by the
  existing suite, so drop it. Typically one spec catches the bug and one catches the
  over-correction — and the second is the one the existing examples rarely cover.
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

`rubocop-rspec` has no `changelog/` directory: append one line to the end of
CHANGELOG.md's `## Master (Unreleased)` section, with no PR link — `- Fix an error for
\`RSpec/Cop\` when <condition>. ([@viralpraxis])` — and add `[@viralpraxis]:
https://github.com/viralpraxis` to the alphabetical link list at the bottom.
`spec/project/changelog_spec.rb` checks both.

Skip the entry entirely when the fix continues an already-merged PR of the same
investigation — one release note covers both. Name that PR in the commit body instead
(`Follow-up to #NNNN, which ...`); the CHANGELOG itself never cross-references. Then
broaden that PR's pending entry so it describes both symptoms, and commit the edit with
the fix — a note covering two fixes has to read like it.

## 4. Commit

Always commit when the work is verified — do not leave it in the working tree.

Subject `Fix an error for \`Cop/Name\` cop` (`Fix an infinite loop for ...` for a
correction loop). The body is `An MRE:`, one fenced `bash`
block, and the attribution line — nothing else:

    An MRE:

    ```bash
    $ bundle exec rubocop --debug --stdin /dev/stdin -a --config <(cat <<'YAML'
    AllCops:
      DisabledByDefault: true
      SuggestExtensions: false
    Layout/ElseAlignment:
      Enabled: true
    YAML
    ) <<'RUBY'
    class A
    rescue
    else
    end
    RUBY
    configuration from /proc/self/fd/11
    Default configuration from config/default.yml
    Inspecting 1 file
    Scanning /dev/stdin
    An error occurred while Layout/ElseAlignment cop was inspecting /dev/stdin:2:0.
    lib/rubocop/cop/mixin/range_help.rb:104:in 'RuboCop::Cop::RangeHelp#effective_column': undefined method 'line' for nil (NoMethodError)

            if range.line == 1 && @processed_source.raw_source.codepoints.first == BYTE_ORDER_MARK
                    ^^^^^
    	from lib/rubocop/cop/mixin/range_help.rb:94:in 'RuboCop::Cop::RangeHelp#column_offset_between'
    	from lib/rubocop/cop/layout/else_alignment.rb:128:in 'RuboCop::Cop::Layout::ElseAlignment#check_alignment'
    	from lib/rubocop/cop/layout/else_alignment.rb:54:in 'RuboCop::Cop::Layout::ElseAlignment#on_rescue'
    	from lib/rubocop/cop/commissioner.rb:109:in 'Kernel#public_send'
    	from lib/rubocop/cop/commissioner.rb:109:in 'block (2 levels) in RuboCop::Cop::Commissioner#trigger_responding_cops'
    ```

    Found by `rubocop-nightly`.

Unlike the runnable block in step 1 this is a **transcript**: prompt the command with
`$ `, and paste the run's own output directly beneath it in the same fence.

- Relativise every absolute path to the repo root (`lib/rubocop/...`,
  `config/default.yml`) — a `/home/<you>/` prefix is noise upstream.
- Put the `An error occurred` line where it belongs in the run (after `Scanning`), not
  wherever the shell happened to flush stderr.
- Cut the paste after the last cop-specific frame plus a frame or two of `commissioner`.
  Keep the raising line and its `^^^^^` excerpt; drop the `1 error occurred:` summary,
  the "Mention the following information" version block, the offence count, and the
  source echo `-a` prints.
- No prose rationale and no root-cause paragraphs — the diff and the changelog carry
  that. Explain the cause in the PR description instead.
- Close with `Found by \`rubocop-nightly\`.` when the fuzzer surfaced it.

## Repo hygiene

Never `git stash` here — check `git branch --show-current` and `git status` first, since
branches may have moved between turns. Assert that scripted edits matched before writing.
