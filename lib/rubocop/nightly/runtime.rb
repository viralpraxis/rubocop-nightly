# frozen_string_literal: true

require 'open3'

module RuboCop
  module Nightly
    module Runtime
      CORE_DEPARTMENTS = %w[
        Bundler Gemspec Layout Lint Metrics Migration Naming Security Style
      ].to_set.freeze

      TERMINATION_GRACE_PERIOD = 2

      # Ruby's verbose mode. RuboCop's own load is warning-free, so anything this surfaces during
      # an inspection came out of the code under test rather than out of the harness.
      RUBY_WARNINGS_FLAG = '-W'

      # Everything Bundler exports when it activates, and the sentinel it stores for
      # variables that were unset before it ran.
      BUNDLER_ENVIRONMENT_PATTERN = /\A(?:BUNDLE_|BUNDLER_)/
      BUNDLER_UNSET = 'BUNDLER_ENVIRONMENT_PRESERVER_INTENTIONALLY_NIL'

      private_constant :BUNDLER_ENVIRONMENT_PATTERN, :BUNDLER_UNSET

      # Builds the environment a child process is handed.
      module ChildEnvironment
        module_function

        # Restores the environment as it stood before Bundler activated, mirroring
        # `Bundler.with_unbundled_env`. The child is deliberately pointed at a *different*
        # Gemfile, so anything the parent's Bundler exported makes it boot against the wrong
        # bundle and die with "the git source ... is not yet checked out". Every `BUNDLE_*`
        # matters, not just the obvious ones — `BUNDLE_LOCKFILE` alone is enough to break it.
        def unbundled
          removals = ENV.keys.grep(BUNDLER_ENVIRONMENT_PATTERN).to_h { [it, nil] }

          removals.merge(bundler_original)
        end

        # Appended rather than assigned: `unbundled` may already be restoring the `RUBYOPT` that
        # stood before Bundler activated, and dropping it would change how the child boots.
        # `bundle exec` re-adds its own `-rbundler/setup` regardless.
        def with_ruby_warnings(environment)
          inherited = environment.fetch('RUBYOPT') { ENV.fetch('RUBYOPT', nil) }

          environment.merge('RUBYOPT' => [inherited, RUBY_WARNINGS_FLAG].compact.join(' ').strip)
        end

        def bundler_original
          ENV.keys.grep(/\ABUNDLER_ORIG_/).to_h do |key|
            original = ENV.fetch(key)

            [key.delete_prefix('BUNDLER_ORIG_'), (original unless original == BUNDLER_UNSET)]
          end
        end
      end

      class << self
        # Runs `bundle exec rubocop` and captures its output.
        #
        # `timeout` bounds the whole invocation: on expiry the child's *process group* is
        # signalled (RuboCop's `--parallel` workers are children of the child) and
        # `ExecutionTimeout` is raised. Unlike wrapping `Open3.capture3` in `Timeout.timeout`,
        # this actually stops the work rather than waiting for it to finish anyway.
        # `warnings` turns on Ruby's own verbose mode in the child. It is off by default because
        # it is only wanted where something reads the warnings back: `compare` logs the whole of
        # stderr, and `--show-cops` treats it as failure detail.
        def execute(
          *command,
          require_plugins: false,
          bundle_gemfile: Pathname(Dir.pwd).join('Gemfile'),
          timeout: nil,
          warnings: false
        )
          environment = unbundled_environment.merge('BUNDLE_GEMFILE' => bundle_gemfile.to_s)

          capture(
            warnings ? with_ruby_warnings(environment) : environment,
            'bundle', 'exec', 'rubocop',
            *(plugin_requires_directive if require_plugins),
            *command,
            timeout: timeout
          )
        rescue Errno::ENOENT => e
          raise ExecutableNotFound, "Unable to run `bundle exec rubocop`: #{e.message}"
        end

        # The highest `AllCops/TargetRubyVersion` that is both understood by the RuboCop being
        # driven and not newer than the interpreter running it. Neither end can be hardcoded:
        # RuboCop 1.76 refuses anything above 3.5, 1.90 accepts up to 4.1 and dropped 3.5
        # entirely, and `compare` deliberately drives arbitrary old revisions.
        def target_ruby_version(bundle_gemfile: Pathname(Dir.pwd).join('Gemfile'))
          current = RUBY_VERSION.split('.').first(2).join('.').to_f
          supported = supported_target_ruby_versions(bundle_gemfile)
          return current if supported.empty?

          supported.select { it <= current }.max || supported.min
        end

        def gems_data_directory = data_directory.join('rubocop-gems').freeze

        def data_directory
          xdg_data_home = ENV.fetch('XDG_DATA_HOME', nil)
          xdg_data_home = File.join(Dir.home, '.local', 'share') if xdg_data_home.nil? || xdg_data_home.empty?

          Pathname(xdg_data_home).expand_path.join('rubocop-nightly').freeze
        end

        def rubocop_repository_uri = 'https://github.com/rubocop/rubocop.git'

        private

        PROBE = <<~RUBY
          require 'rubocop'
          versions = if RuboCop::TargetRuby.respond_to?(:supported_versions)
                       RuboCop::TargetRuby.supported_versions
                     else
                       RuboCop::TargetRuby::KNOWN_RUBIES
                     end
          puts versions.join(',')
        RUBY
        private_constant :PROBE

        # Memoised per Gemfile: the probe is a subprocess, and a single run builds several
        # configurations against the same bundle.
        def supported_target_ruby_versions(bundle_gemfile)
          # rubocop:disable ThreadSafety/ClassInstanceVariable
          @supported_target_ruby_versions ||= {}
          @supported_target_ruby_versions[bundle_gemfile.to_s] ||= probe_target_ruby_versions(bundle_gemfile)
          # rubocop:enable ThreadSafety/ClassInstanceVariable
        end

        def probe_target_ruby_versions(bundle_gemfile)
          stdout, _stderr, status = Open3.capture3(
            unbundled_environment.merge('BUNDLE_GEMFILE' => bundle_gemfile.to_s),
            'bundle', 'exec', 'ruby', '-e', PROBE
          )
          return [] unless status.success?

          stdout.split(',').filter_map { Float(it, exception: false) }
        rescue SystemCallError
          []
        end

        def unbundled_environment = ChildEnvironment.unbundled

        def with_ruby_warnings(environment) = ChildEnvironment.with_ruby_warnings(environment)

        def capture(environment, *arguments, timeout:)
          Open3.popen3(environment, *arguments, pgroup: true) do |stdin, stdout, stderr, wait_thread|
            stdin.close
            # Drained concurrently so a child producing more than one pipe buffer of output
            # cannot deadlock while we wait for it.
            readers = [stdout, stderr].map { |io| Thread.new { io.read } } # rubocop:disable ThreadSafety/NewThread

            timed_out = !wait_thread.join(timeout)
            terminate(wait_thread) if timed_out

            captured = readers.map(&:value)
            raise ExecutionTimeout, "`#{arguments.join(' ')}` exceeded #{timeout}s and was terminated" if timed_out

            [*captured, wait_thread.value]
          end
        end

        # `pgroup: true` made the child a process group leader, so negating its pid reaches
        # every worker it forked.
        def terminate(wait_thread)
          signal_group(wait_thread.pid, 'TERM')
          return if wait_thread.join(TERMINATION_GRACE_PERIOD)

          signal_group(wait_thread.pid, 'KILL')
          wait_thread.join
        end

        def signal_group(pid, signal)
          Process.kill(signal, -pid)
        rescue Errno::ESRCH, Errno::EPERM
          nil
        end

        def plugin_requires_directive
          RuboCop::Nightly::Runtime::PluginRegistry
            .all_names
            .flat_map { ['--plugin', it] }
        end
      end
    end
  end
end
