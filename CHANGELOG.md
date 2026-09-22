## [Unreleased]

- Add five more repositories to the `git` corpus, each measured to fit a nightly budget
  with room to spare. One pass over each, four workers, times 39 configuration variants:
  `Homebrew/brew` 1.4h, `metasploit/metasploit-framework` 0.9h, `fastlane/fastlane` 0.6h,
  `redmine/redmine` 0.6h, `opal/opal` 0.25h.

  They were picked for what the corpus did not already have. Homebrew has the densest
  modern syntax measured anywhere: 28% of its files carry a squiggly heredoc, 26% a
  leading-dot chain, 4.9% an endless method, on top of Sorbet signatures and the Formula
  DSL. Metasploit brings 31 files with `=begin` blocks, 14 with `__END__`, and the only
  `.builder` and `.fcgi` files in the corpus. Fastlane is the only source that populates
  `RUBY_FILENAMES` at all - `Fastfile`, `Appfile`, `Brewfile`, `Podfile` - a code path
  that until now was never exercised. Redmine is pre-modern Rails idiom, which the
  modern applications in the corpus do not cover. Opal is compiler code, with
  `class_eval`/`define_method` in 8% of its files.

  Homebrew and Metasploit exclude `**/vendor/**/*`: vendored copies of published gems
  (396 files under `vendor/bundle`) and of Rails 2 and tzinfo (815 files) respectively.
  Both are third-party snapshots the `rubygems` source already covers, and dropping them
  takes Metasploit from 115.8s to 83.7s a pass.

- Add `ruby/ruby` to the `git` corpus. Its `lib/`, `test/` and `ext/` trees are the widest
  span of Ruby idiom available anywhere: two decades of style in one checkout, 99 files
  carrying a non-UTF-8 magic comment, and the only `BEGIN {}`, `__END__` and flip-flop
  usage in the corpus.
- Support an `exclude` list of globs on `git` source entries. Two parts of `ruby/ruby`
  have to stay out, and neither can be kept out any other way: RuboCop ignores
  `AllCops: Exclude` for paths named explicitly on the command line, which is how the
  fuzzer invokes it.

  `enc/trans/*-tbl.rb` are generated encoding tables whose cost is out of all proportion
  to what they can find. `gb18030-tbl.rb` alone is 190k AST nodes and takes 222s to
  inspect once; the 61 of them take 424s. Because the corpus is sorted and sliced in
  order, all 61 land in the first batch of eight, and at 39 configuration variants per
  batch that batch costs 5.15h against a 5.75h nightly budget - the run would die inside
  batch two having seen 1,100 of 7,502 files. Excluding them takes the same batch from
  476s to 48s, in line with every other batch, and brings the whole repository to ~4.1h.

  `spec/**/*` is a vendored copy of the `ruby/spec` entry: 5,024 files, of which 4,426 are
  byte-identical to what that source already contributes. `Corpus` deduplicates by digest,
  but only within a source, and the nightly workflow gives each repository its own job.

## [0.1.0] - 2024-12-27

- Initial release
