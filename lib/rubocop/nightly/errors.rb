# frozen_string_literal: true

module RuboCop
  module Nightly
    class Error < StandardError
    end

    # Raised when `bundle exec rubocop` cannot be spawned at all.
    class ExecutableNotFound < Error
    end

    # Raised when a RuboCop invocation exceeded its deadline and was killed.
    class ExecutionTimeout < Error
    end

    # Raised when a RuboCop invocation failed and its output cannot be trusted.
    class ExecutionError < Error
    end

    # Raised when the environment is not set up well enough to run a command.
    class ConfigurationError < Error
    end
  end
end
