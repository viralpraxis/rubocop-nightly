# frozen_string_literal: true

RSpec.describe RuboCop::Nightly::Source::Entry do
  describe '#excludes?' do
    subject(:entry) { described_class.new(path: '/corpus', exclude: exclude) }

    let(:exclude) { ['spec/**/*', 'enc/trans/*-tbl.rb'] }

    it 'matches a file under an excluded directory' do
      expect(entry).to be_excludes('/corpus/spec/ruby/core/array/first_spec.rb')
    end

    it 'matches a file the glob names directly' do
      expect(entry).to be_excludes('/corpus/enc/trans/gb18030-tbl.rb')
    end

    it 'leaves a sibling the glob does not name alone' do
      expect(entry).not_to be_excludes('/corpus/enc/trans/single_byte.rb')
    end

    it 'leaves an unrelated file alone' do
      expect(entry).not_to be_excludes('/corpus/lib/resolv.rb')
    end

    context 'with a bare directory name' do
      let(:exclude) { ['spec'] }

      it 'excludes everything below it' do
        expect(entry).to be_excludes('/corpus/spec/ruby/core/array/first_spec.rb')
      end
    end

    context 'with no exclusions' do
      let(:exclude) { [] }

      it 'excludes nothing' do
        expect(entry).not_to be_excludes('/corpus/spec/a_spec.rb')
      end
    end
  end

  describe '.new' do
    it 'defaults to excluding nothing' do
      expect(described_class.new(path: '/corpus').exclude).to be_empty
    end

    it 'drops a trailing separator so relative paths line up' do
      expect(described_class.new(path: '/corpus/', exclude: ['spec']).path).to eq('/corpus')
    end
  end
end
