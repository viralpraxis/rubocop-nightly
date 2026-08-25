# frozen_string_literal: true

# The fixture Gemfiles pin specific RuboCop versions and are not installed by default.
# Tests that need them say so explicitly and skip with an actionable message, rather than
# being permanently disabled by a bare `skip: :ci_fix` tag.
module BundleHelpers
  def skip_unless_bundle_installed(gemfile)
    return if self.class.bundle_installed?(gemfile)

    skip "fixture bundle not installed; run `BUNDLE_GEMFILE=#{gemfile} bundle install`"
  end

  def self.included(base)
    base.extend(ClassMethods)
  end

  module ClassMethods
    def bundle_installed?(gemfile)
      Bundler.with_unbundled_env do
        system({ 'BUNDLE_GEMFILE' => gemfile.to_s }, 'bundle', 'check', out: File::NULL, err: File::NULL)
      end
    end
  end
end

RSpec.configure { it.include BundleHelpers }
