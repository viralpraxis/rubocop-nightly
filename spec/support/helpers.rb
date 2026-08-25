# frozen_string_literal: true

# Defined in a module included into example groups rather than as top-level methods on
# Object, which would leak into every object in the suite and defeat `disable_monkey_patching!`.
module SpecHelpers
  def with_environment_variable(variable_name, variable_value)
    original_variable_value = ENV.fetch(variable_name, nil)

    ENV[variable_name] = variable_value

    yield
  ensure
    ENV[variable_name] = original_variable_value
  end

  def fixture_path(relative_path)
    File.expand_path("../fixtures/#{relative_path}", __dir__)
  end
end

RSpec.configure { it.include SpecHelpers }
