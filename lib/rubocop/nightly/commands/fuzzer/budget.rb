# frozen_string_literal: true

module RuboCop
  module Nightly
    module Commands
      module Fuzzer
        # Bounds reduction so that a night which finds thirty crashes cannot turn into an hour of
        # shrinking. Never raises: callers check the return value and keep whatever they have,
        # because a partially reduced example is still far better than none.
        class Budget
          def initialize(seconds:, calls:, per_call_timeout: 60)
            @seconds = seconds
            @calls = calls
            @per_call_timeout = per_call_timeout
            @spent = 0
            @started_at = monotonic_now
          end

          attr_reader :spent, :per_call_timeout

          # `mandatory` claims are always granted. Verifying the final example is not optional:
          # refusing it would silently throw away every reduction already paid for, which is how
          # this first went wrong.
          # rubocop:disable-next Naming/PredicateMethod -- `claim!` acts; the boolean reports whether it did
          def claim!(mandatory: false)
            return false if !mandatory && exhausted?

            @spent += 1
            true
          end

          def exhausted? = spent >= calls || elapsed >= seconds

          def elapsed = monotonic_now - @started_at

          def to_s = format('%<calls>d call(s), %<seconds>.1fs', calls: spent, seconds: elapsed)

          private

          attr_reader :seconds, :calls

          def monotonic_now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end
      end
    end
  end
end
