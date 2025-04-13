# frozen_string_literal: true

require 'rubocop'
require 'rubocop/nightly/null_formatter'

RSpec.describe RuboCop::Nightly::NullFormatter do
  subject(:formatter) { described_class.new(File::NULL) }

  describe '#started' do
    it 'does not raise' do
      expect { formatter.started }.not_to raise_error
    end
  end

  describe '#file_started' do
    it 'does not raise' do
      expect { formatter.file_started }.not_to raise_error
    end
  end

  describe '#file_finished' do
    it 'does not raise' do
      expect { formatter.file_finished }.not_to raise_error
    end
  end

  describe '#finished' do
    it 'does not raise' do
      expect { formatter.finished }.not_to raise_error
    end
  end
end
