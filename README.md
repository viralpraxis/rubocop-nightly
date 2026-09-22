# RuboCop::Nightly

`rubocop-nightly` is a regression testing tool for RuboCop. It enables testing core cops alongside official and third-party extensions, exploring RuboCop's configuration state space, and analyzing Ruby code from various sources.

## Installation

At this moment, `rubocop-nightly` is distributed as a git repository. Simply run `git clone` and you're set up.

NOTE: Only MRI 4.0 is supported (see `.ruby-version`).

## Usage

> **Warning**
>
> Prior to [this patch](https://github.com/rubocop/rubocop/pull/14073), RuboCop was not able to investigate folders with hidden directory (`/.`) segments. If you need to run RuboCop which does not contain this patch, specify `XDG_DATA_HOME` so that it does not contain hidden segments.

### Comparison

RuboCop Nightly's `compare` command can be used to detect offenses difference between two RuboCop revisions.
You can simpliy run

```bash
bin/rubocop-nightly compare --from 53e5d198f --to master --source https://github.com/rails/rails.git
```

or

```bash
bin/rubocop-nightly compare --from https://github.com/viralpraxis/rubocop.git:53e5d198f --to master --source https://github.com/rails/rails.git:main
```

or even

```bash
bin/rubocop-nightly compare --from https://github.com/viralpraxis/rubocop.git:53e5d198f --to https://github.com/Earlopain/rubocop.git:master --source https://github.com/rails/rails.git:feature-1
```

### Fuzzing

Before running RuboCop Nightly's `fuzzer` command, acquire the latest RuboCop core and plugins by executing the following Rake task:

```console
bundle exec rake gems:install
```

This installs the preconfigured gems into either:

- `$XDG_DATA_HOME/rubocop-nightly/rubocop-gems`, if `XDG_DATA_HOME` is set;
- `~/.local/share/rubocop-nightly/rubocop-gems`, otherwise.

Set `GEMS_SCOPE=core` to install RuboCop itself and nothing else, which pairs with the fuzzer's
`--no-plugins`: there is no point cloning a dozen extensions from `master` when the run is
confined to RuboCop's own cops. Any other value (or none) installs everything in
[`config/gems.yml`](./config/gems.yml).

After setting up, you can run regression tests on Ruby code fetched from one of the supported **sources**:

1. `rubygems`

   Fetch gems published to https://rubygems.org within the last day, from the
   [timeframe feed](https://rubygems.org/api/v1/timeframe_versions.json), read 30 entries
   per page until a page comes back empty. rubygems.org takes roughly 450 new versions
   across roughly 260 distinct gems on a weekday, appreciably fewer at the weekend, so a
   day's window is a few hundred entries and a dozen or so requests.

   Platform-specific builds are fetched separately, and every download is verified against
   the checksum the API reports.

   Example:

   ```console
   bin/rubocop-nightly fuzzer --source rubygems
   ```

   `--rubygems-limit` caps the run at the N most recently published gems. The feed is
   ordered oldest first, so it is reversed before the cap applies; the cap is applied after
   the one-day window, so stale entries cannot consume the slots. Fewer than N are returned
   when the window holds fewer - which is what a limit above a few hundred will hit.

   ```console
   bin/rubocop-nightly fuzzer --source rubygems --rubygems-limit 200
   ```

2. `git`

   Fetch [preconfigured git repositories](./config/git.yml).

   Example:

   ```console
   bin/rubocop-nightly fuzzer --source git --git-sources ./config/git.yml
   ```

   Repositories are shallow-cloned on first use and fast-forwarded to the current branch
   tip on subsequent runs.

   An entry may carry an `exclude` list of globs, matched against paths relative to the
   repository root, to keep part of a checkout out of the corpus:

   ```yaml
   - url: https://github.com/ruby/ruby.git
     branch: master
     exclude:
       - spec/**/*
       - enc/trans/*-tbl.rb
   ```

   A glob naming a directory (`spec`, `spec/**/*`) excludes everything below it.

3. `mirror` (*experimental*)

   Analyze a local mirror maintained with [`rubygems-mirror`](https://github.com/rubygems/rubygems-mirror).
   The path may be a directory or a glob. A directory is walked recursively, so it works just as
   well against an ordinary source tree as against a mirror holding one directory per gem.

   Example:

   ```console
   bin/rubocop-nightly fuzzer --source mirror --mirror-path /var/opt/rubygems-mirror/latest
   ```

### CLI options

All sources support the following CLI options:

- `--batch-size` (default: `1000`)

   Number of Ruby **files** to process per batch. Source entries (extracted gems, repository
   checkouts, mirror directories) are expanded into their Ruby files first, and files whose
   content has already been seen are dropped — a 50-gem sample of rubygems.org collapses from
   17,613 files to 6,541 distinct ones.

   Smaller batches limit what a `--batch-timeout` loses; larger ones amortise RuboCop's
   start-up cost (~0.5s per invocation against ~0.05s per file). The default keeps start-up
   overhead near 1%.

- `--batch-timeout`

   Limits the processing time for a single batch, in seconds. On expiry the RuboCop child and
   its `--parallel` workers are killed by process group, so a cop that hangs on a pathological
   file cannot stall the run.

- `--reduce` (default: off)

   After a crash is detected, shrink it to a minimal reproducible example: the offending cop
   alone, a few lines of configuration, and the smallest source that still triggers it. Writes
   `mre.rb`, `mre.yml` and a runnable `mre.sh` next to the raw reproduction.

   It costs a handful of extra RuboCop invocations per distinct crash (typically 2–6, a few
   seconds), but a large input can take considerably longer, so it is opt-in. Use `--no-reduce`
   to be explicit.

- `--autocorrect` (default: off)

   Also exercise RuboCop's correction path, which is roughly half of a cop's code and is never
   reached by a read-only run. Three things are reported that a read-only run cannot see:

   - a cop that raises while correcting rather than while inspecting;
   - an *infinite correction loop*, which RuboCop warns about on stderr and steps over, so it
     never reaches the "an error occurred" path;
   - a **broken correction** — source that parsed before the correction and does not parse
     after it. This one needs no judgement: it is always a bug.

   **The corpus is never modified.** `--autocorrect` rewrites whatever it is pointed at, so each
   batch is copied into a throwaway directory first and RuboCop is pointed at the copies. Each
   copy keeps its original absolute path underneath the temporary root, so path-sensitive cops
   such as `Naming/FileName` and `RSpec/SpecFilePathFormat` still behave the same way. The
   directory is removed when the batch ends.

   Use `--no-autocorrect` to be explicit.

- `--plugins` (default: on)

   Fuzz the extension cops alongside the core ones. `--no-plugins` confines the run to RuboCop
   itself: `--show-cops` is asked for the core set alone, the `plugins`/`require` keys are dropped
   from the generated configuration, and no `--plugin` directive is passed to the RuboCop child.
   That last part matters — loading a plugin registers its cops *and* merges its own defaults, so
   requiring one against a core-only configuration would quietly put every plugin cop back into
   the run.

   Against the current [`config/gems.yml`](./config/gems.yml) this is the difference between
   **1065** cops and **613**.

   The nightly workflows pass `--no-plugins` by default. Dispatch them with `plugins: true` to
   put the extensions back for a one-off run.

- `--only-show-types` (default: every type)

   Report only the named issue types, comma separated:

   ```console
   bin/rubocop-nightly fuzzer --source rubygems --autocorrect --only-show-types broken-correction
   ```

   This narrows the **report**, not the run. Every type is still collected, deduplicated and
   counted in the closing summary, and every reproduction is still written to disk — so hiding a
   kind cannot quietly turn a failing night green, and widening the filter next time does not mean
   re-fuzzing to get the evidence back.

- `--log-level` (default: `INFO`)

   One of `DEBUG`, `INFO`, `WARN`, `ERROR`, `FATAL`, `UNKNOWN`. Logs go to stderr, so the
   `compare` report on stdout stays machine-readable.

### Ruby warnings

The RuboCop child is run under Ruby's verbose mode (`RUBYOPT=-W`), and any warning it emits is
collected and reported. RuboCop's own load is warning-free, so a warning that appears during a run
came out of the code under test — an uninitialised variable, a redefined method, a deprecated
call. Warnings are deduplicated across the run (with the Bundler checkout revision masked out of
the path, so one warning from two checkouts of a gem is not counted twice).

They are reported but do **not** affect the exit status: they are worth reading, but a single
noisy dependency should not be able to turn an otherwise clean night red.

### Reading the log

Each defect is reported on exactly one line, tagged with its issue type and ending in the example
that reproduces it:

```
ERROR: [exception] [<reproduction directory>] Style/Thing: /path/bug.rb:2:1 -> mre/Style-Thing-1a2b3c4d/mre.sh (whole file)
ERROR: [broken-correction] [<reproduction directory>] /path/x.rb: unexpected 'end' -> mre/broken-correction-x-5e6f7a8b/mre.sh
ERROR: [infinite-loop] /path/y.rb (Layout/LineLength, Style/MutableConstant)
```

There are three issue types:

| Type | Meaning |
| --- | --- |
| `exception` | a cop raised while inspecting or correcting |
| `broken-correction` | `--autocorrect` turned source that parsed into source that does not |
| `infinite-loop` | corrections never settled, so RuboCop gave up on the file |

The script is named relative to the reproduction directory the same line already carries. Where
`--reduce` ran, the trailing note carries the exception class and how far the source shrank; where
no example could be written, the line ends with `-> no MRE: <reason>` instead.

Ruby warnings are reported at `WARN` rather than `ERROR` and are not one of the issue types.

### Exit status

| Status | Meaning |
| --- | --- |
| `0` | Success — no cop errors detected (`fuzzer`), or no offense differences (`compare`) |
| `1` | Cop errors detected, a batch failed, or the run could not complete |
| `2` | Invalid command-line usage |

Configurations that reproduce a detected cop error are written to
`<data directory>/fuzzer/reproductions/` and referenced in the log line reporting the error.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests (a few integration examples are skipped unless the fixture bundles under `spec/fixtures/gemfiles/` are installed; the skip message tells you the command). You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/viralpraxis/rubocop-nightly. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/viralpraxis/rubocop-nightly/blob/main/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the RuboCop::Nightly project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/viralpraxis/rubocop-nightly/blob/main/CODE_OF_CONDUCT.md).
