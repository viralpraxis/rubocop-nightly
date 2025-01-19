# RuboCop::Nightly

`rubocop-nightly` is a regression testing tool for RuboCop. It enables testing core cops alongside official and third-party extensions, exploring RuboCop's configuration state space, and analyzing Ruby code from various sources.

## Installation

At this moment, `rubocop-nightly` is distributed as a git repository. Simply run `git clone` and you're set up.

NOTE: Only MRI 3.4 is supported.

## Usage

Before running `rubocop-nightly`, acquire the latest RuboCop core and plugins by executing the following Rake task:

```console
bundle exec rake gems:fetch
```

This installs the preconfigured gems into either:

- `$XDG_DATA_HOME/rubocop-nightly/rubocop-gems`, if `XDG_DATA_HOME` is set;
- `~/.local/share/rubocop-nightly/rubocop-gems`, otherwise.

After setting up, you can run regression tests on Ruby code fetched from one of the supported **sources**:

1. `rubygems`

   Fetch the latest 50 gem snapshots from https://rubygems.org.

   Example:

   ```console
   bin/rubocop-nightly --source rubygems
   ```

2. `git`

   Fetch [preconfigured git repositories](./config/git.yml).

   Example:

   ```console
   bin/rubocop-nightly --source git --git-source ./config/git.yml
   ```

3. `mirror` (*expirimental*)

   Currently a no-op. Designed to run rubocop-nightly against a local mirror using [`rubygems-mirror`](https://github.com/rubygems/rubygems-mirror)

   Example:

   ```console
   bin/rubocop-nightly --source mirror --mirror-path /var/opt/rubygems-mirror/latest
   ```

### CLI options

All sources support the following CLI options:

- `--batch-size`

   Specifies the number of files to process per batch. If not set, rubocop-nightly will process all files in one go.

- `--batch-timeout`

   Limits the processing time for a single batch in seconds. Useful to prevent RuboCop from hanging on large files.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/viralpraxis/rubocop-nightly. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/viralpraxis/rubocop-nightly/blob/main/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the RuboCop::Nightly project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/viralpraxis/rubocop-nightly/blob/main/CODE_OF_CONDUCT.md).
