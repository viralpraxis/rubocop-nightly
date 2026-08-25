# frozen_string_literal: true

RSpec.describe RuboCop::Nightly::Source do
  describe '.build' do
    it 'builds a rubygems source' do
      expect(described_class.build(:rubygems)).to be_a(described_class::Rubygems)
    end

    it 'accepts a string type' do
      expect(described_class.build('mirror', mirror_path: '/tmp')).to be_a(described_class::Mirror)
    end

    it 'lists the valid sources when given an unknown one' do
      expect { described_class.build(:nope) }
        .to raise_error(ArgumentError, /unknown source :nope.*rubygems, mirror, git/)
    end
  end
end
