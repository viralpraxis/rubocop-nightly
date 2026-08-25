# frozen_string_literal: true

require_relative 'lib/rubocop/nightly/version'

Gem::Specification.new do |spec|
  spec.name = 'rubocop-nightly'
  spec.version = RuboCop::Nightly::VERSION
  spec.authors = ['Iaroslav Kurbatov']
  spec.email = ['iaroslav2k@gmail.com']

  spec.summary = 'Regression testing tool for RuboCop'
  spec.description = <<~DESCRIPTION
    rubocop-nightly is a regression testing tool for RuboCop. It exercises core cops alongside
    official and third-party extensions, explores RuboCop's configuration state space, and
    analyzes Ruby code fetched from RubyGems, git repositories or a local mirror.
  DESCRIPTION
  spec.homepage = 'https://github.com/viralpraxis/rubocop-nightly'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 4.0.0'

  spec.metadata['allowed_push_host'] = 'https://rubygems.org'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = "#{spec.homepage}/tree/main"
  spec.metadata['changelog_uri'] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata['bug_tracker_uri'] = "#{spec.homepage}/issues"
  spec.metadata['rubygems_mfa_required'] = 'true'

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[test/ spec/ features/ .git .github appveyor Gemfile AUDIT.md])
    end
  end

  spec.bindir = 'bin'
  spec.executables = ['rubocop-nightly']
  spec.require_paths = ['lib']
end
