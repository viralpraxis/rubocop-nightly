# frozen_string_literal: true

module RuboCop
  module Nightly
    class Error < StandardError
    end

    class ExecutableNotFound < Error
    end

    class ExecutionTimeout < Error
    end

    class ExecutionError < Error
    end

    class ConfigurationError < Error
    end
  end
end
