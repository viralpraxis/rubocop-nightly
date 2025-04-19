# frozen_string_literal: true

def with_environment_variable(variable_name, variable_value)
  original_variable_value = ENV.fetch(variable_name, nil)

  ENV[variable_name] = variable_value

  yield
ensure
  ENV[variable_name] = original_variable_value
end

def fixture_path(relative_path)
  File.expand_path("../../fixtures/#{relative_path}", __FILE__)
end
