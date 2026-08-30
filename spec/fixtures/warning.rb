# frozen_string_literal: true

# Loaded into the RuboCop process to prove Ruby verbose mode reached it: this is the smallest
# thing that makes the interpreter say something on stderr.
1 == 1 # rubocop:disable Lint/BinaryOperatorWithIdenticalOperands
