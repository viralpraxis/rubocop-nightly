# frozen_string_literal: true

RSpec.describe RuboCop::Nightly::Corpus do
  let(:root) { Dir.mktmpdir('rubocop-nightly-corpus') }

  after { FileUtils.remove_entry(root) }

  def write(relative_path, contents)
    path = File.join(root, relative_path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, contents)
    path
  end

  describe '#files' do
    it 'expands a directory into its Ruby files' do
      a = write('lib/a.rb', 'a')
      b = write('lib/nested/b.rake', 'b')
      write('README.md', 'not ruby')
      write('lib/data.json', '{}')

      expect(described_class.new([root]).files).to contain_exactly(a, b)
    end

    it 'recognises Ruby files that have no extension' do
      rakefile = write('Rakefile', 'task :default')

      expect(described_class.new([root]).files).to contain_exactly(rakefile)
    end

    it 'keeps one representative per distinct content', :aggregate_failures do
      write('x86/lib/thing.rb', 'identical')
      write('arm/lib/thing.rb', 'identical')
      distinct = write('lib/other.rb', 'different')

      files = described_class.new([root]).files

      expect(files.size).to eq(2)
      expect(files).to include(distinct)
    end

    it 'is deterministic about which duplicate it keeps' do
      write('b/thing.rb', 'identical')
      first = write('a/thing.rb', 'identical')

      expect(described_class.new([root]).files).to eq([first])
    end

    it 'accepts plain file entries as well as directories' do
      a = write('lib/a.rb', 'a')

      expect(described_class.new([a]).files).to contain_exactly(a)
    end

    it 'ignores entries that do not exist' do
      expect(described_class.new(['/nope/nowhere']).files).to be_empty
    end

    it 'ignores non-Ruby file entries' do
      expect(described_class.new([write('notes.txt', 'x')]).files).to be_empty
    end

    it 'handles a nil entry list' do
      expect(described_class.new(nil).files).to be_empty
    end

    it 'leaves out files matched by a source exclusion' do
      kept = write('lib/a.rb', 'a')
      write('spec/ruby/core/b_spec.rb', 'b')
      write('enc/trans/gb18030-tbl.rb', 'c')
      entry = RuboCop::Nightly::Source::Entry.new(path: root, exclude: ['spec/**/*', 'enc/trans/*-tbl.rb'])

      expect(described_class.new([entry]).files).to contain_exactly(kept)
    end

    it 'keeps files the exclusions do not match' do
      kept = write('enc/trans/single_byte.rb', 'a')
      entry = RuboCop::Nightly::Source::Entry.new(path: root, exclude: ['enc/trans/*-tbl.rb'])

      expect(described_class.new([entry]).files).to contain_exactly(kept)
    end

    it 'excludes a whole directory named without a glob' do
      kept = write('lib/a.rb', 'a')
      write('spec/nested/b.rb', 'b')
      entry = RuboCop::Nightly::Source::Entry.new(path: root, exclude: ['spec'])

      expect(described_class.new([entry]).files).to contain_exactly(kept)
    end

    it 'reports what the exclusions left out' do
      allow(RuboCop::Nightly.logger).to receive(:info)
      write('lib/a.rb', 'a')
      write('spec/b.rb', 'b')
      entry = RuboCop::Nightly::Source::Entry.new(path: root, exclude: ['spec/**/*'])

      described_class.new([entry]).files

      expect(RuboCop::Nightly.logger).to have_received(:info).with(/1 file\(s\) left out by source exclusions/)
    end

    it 'reports the reduction' do
      allow(RuboCop::Nightly.logger).to receive(:info)
      write('x86/thing.rb', 'identical')
      write('arm/thing.rb', 'identical')

      described_class.new([root]).files

      expect(RuboCop::Nightly.logger).to have_received(:info).with(/1 distinct Ruby files from 2.*50\.0% skipped/)
    end
  end
end
