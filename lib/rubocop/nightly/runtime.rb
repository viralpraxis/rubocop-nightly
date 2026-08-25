# frozen_string_literal: true

require 'open3'

module RuboCop
  module Nightly
    module Runtime
      CORE_DEPARTMENTS = %w[
        Bundler Gemspec Layout Lint Metrics Migration Naming Security Style
      ].to_set.freeze

      # Grace period between SIGTERM and SIGKILL when a run exceeds its deadline.
      TERMINATION_GRACE_PERIOD = 2

      class << self
        # Runs `bundle exec rubocop` and captures its output.
        #
        # `timeout` bounds the whole invocation: on expiry the child's *process group* is
        # signalled (RuboCop's `--parallel` workers are children of the child) and
        # `ExecutionTimeout` is raised. Unlike wrapping `Open3.capture3` in `Timeout.timeout`,
        # this actually stops the work rather than waiting for it to finish anyway.
        def execute(
          *command,
          require_plugins: false,
          bundle_gemfile: Pathname(Dir.pwd).join('Gemfile'),
          timeout: nil
        )
          capture(
            { 'BUNDLE_GEMFILE' => bundle_gemfile.to_s },
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
            { 'BUNDLE_GEMFILE' => bundle_gemfile.to_s }, 'bundle', 'exec', 'ruby', '-e', PROBE
          )
          return [] unless status.success?

          stdout.split(',').filter_map { Float(it, exception: false) }
        rescue SystemCallError
          []
        end

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
