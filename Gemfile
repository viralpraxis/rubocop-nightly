# frozen_string_literal: true

source 'https://rubygems.org'

gemspec

gem 'irb'
gem 'logger'
gem 'racc'
gem 'rake', '~> 13.0'
gem 'rspec', '~> 3.0'
gem 'rubocop', '~> 1.21'
gem 'rubocop-performance'
gem 'rubocop-rake'
gem 'rubocop-rspec'
gem 'rubocop-thread_safety'
gem 'ruby-lsp'
gem 'simplecov'

local_gemfile = File.expand_path('Gemfile.local', __dir__)
eval_gemfile local_gemfile if File.exist?(local_gemfile)
