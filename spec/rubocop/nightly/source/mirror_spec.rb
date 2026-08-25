# frozen_string_literal: true

RSpec.describe RuboCop::Nightly::Source::Mirror do
  let(:root) { Dir.mktmpdir('rubocop-nightly-mirror') }

  before do
    FileUtils.mkdir_p(File.join(root, 'gem-a'))
    FileUtils.mkdir_p(File.join(root, 'gem-b'))
    File.write(File.join(root, 'specs.4.8.gz'), 'binary')
    File.write(File.join(root, '.hidden'), 'x')
  end

  after { FileUtils.remove_entry(root) }

  describe '#fetch' do
    it 'returns only directories, prefixed with the mirror path' do
      expect(described_class.new(mirror_path: root).fetch)
        .to contain_exactly(File.join(root, 'gem-a'), File.join(root, 'gem-b'))
    end

    it 'returns paths that actually exist' do
      expect(described_class.new(mirror_path: root).fetch).to all(satisfy { File.exist?(it) })
    end

    context 'with a glob pattern' do
      it 'does not re-join the pattern onto already-complete paths' do
        expect(described_class.new(mirror_path: File.join(root, '*')).fetch)
          .to contain_exactly(File.join(root, 'gem-a'), File.join(root, 'gem-b'))
      end

      it 'returns paths that actually exist' do
        expect(described_class.new(mirror_path: File.join(root, '*')).fetch)
          .to all(satisfy { File.exist?(it) })
      end
    end

    context 'when the mirror path does not exist' do
      it 'raises a descriptive error' do
        expect { described_class.new(mirror_path: '/nope/nowhere').fetch }
          .to raise_error(RuboCop::Nightly::ConfigurationError, /not a directory/)
      end
    end
  end
end
