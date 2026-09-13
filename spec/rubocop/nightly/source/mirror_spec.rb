# frozen_string_literal: true

RSpec.describe RuboCop::Nightly::Source::Mirror do
  let(:root) { Dir.mktmpdir('rubocop-nightly-mirror') }

  before do
    FileUtils.mkdir_p(File.join(root, 'gem-a', 'lib'))
    FileUtils.mkdir_p(File.join(root, 'gem-b'))
    File.write(File.join(root, 'gem-a', 'lib', 'a.rb'), "A = 1\n")
    File.write(File.join(root, 'gem-b', 'b.rb'), "B = 1\n")
    File.write(File.join(root, 'specs.4.8.gz'), 'binary')
  end

  after { FileUtils.remove_entry(root) }

  def corpus_for(path) = RuboCop::Nightly::Corpus.new(described_class.new(mirror_path: path).fetch).files

  describe '#fetch' do
    it 'hands the mirror path over for the corpus to walk' do
      expect(described_class.new(mirror_path: root).fetch).to eq([root])
    end

    it 'reaches the Ruby files nested under it' do
      expect(corpus_for(root))
        .to contain_exactly(File.join(root, 'gem-a', 'lib', 'a.rb'), File.join(root, 'gem-b', 'b.rb'))
    end

    # The mirror source was written for a rubygems mirror, where every child is a gem directory.
    # Pointed at an ordinary source directory it used to report "Nothing to analyze", because the
    # loose files were filtered out before the corpus ever saw them.
    context 'when the path holds Ruby files rather than one directory per gem' do
      let(:plain) { Dir.mktmpdir('rubocop-nightly-plain') }

      before do
        File.write(File.join(plain, 'client.rb'), "C = 1\n")
        File.write(File.join(plain, 'wrapper.rb'), "W = 1\n")
        File.write(File.join(plain, 'README.md'), 'not ruby')
      end

      after { FileUtils.remove_entry(plain) }

      it 'analyses them' do
        expect(corpus_for(plain))
          .to contain_exactly(File.join(plain, 'client.rb'), File.join(plain, 'wrapper.rb'))
      end

      it 'leaves the non-Ruby files out, which the corpus already knows how to do' do
        expect(corpus_for(plain)).not_to include(File.join(plain, 'README.md'))
      end
    end

    context 'with a glob pattern' do
      it 'does not re-join the pattern onto already-complete paths' do
        expect(described_class.new(mirror_path: File.join(root, '*')).fetch)
          .to all(satisfy { File.exist?(it) })
      end

      it 'yields the same corpus as naming the directory itself' do
        expect(corpus_for(File.join(root, '*'))).to match_array(corpus_for(root))
      end

      it 'accepts a pattern that matches files rather than directories' do
        expect(corpus_for(File.join(root, 'gem-b', '*.rb'))).to contain_exactly(File.join(root, 'gem-b', 'b.rb'))
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
