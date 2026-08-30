# frozen_string_literal: true

RSpec.describe RuboCop::Nightly::Commands::Fuzzer::Workspace do
  let(:corpus) { Pathname(Dir.mktmpdir('rubocop-nightly-corpus')) }
  let(:spec_file) { corpus.join('lib', 'thing_spec.rb') }
  let(:plain_file) { corpus.join('lib', 'thing.rb') }

  before do
    corpus.join('lib').mkpath
    spec_file.write("# spec\n")
    plain_file.write("# plain\n")
  end

  after { FileUtils.remove_entry(corpus) }

  def target_paths = [spec_file.to_s, plain_file.to_s]

  describe '.open' do
    it 'hands back the corpus paths untouched when not correcting' do
      described_class.open(target_paths, autocorrect: false) do |workspace|
        expect(workspace.paths).to eq(target_paths)
      end
    end

    it 'hands back copies when correcting' do
      described_class.open(target_paths, autocorrect: true) do |workspace|
        expect(workspace.paths).to all(satisfy { !target_paths.include?(it) })
      end
    end
  end

  describe described_class::ReadOnly do
    it 'has nothing to translate' do
      described_class.open(['/a.rb']) do |workspace|
        expect(workspace.original_for('/a.rb')).to eq('/a.rb')
      end
    end

    it 'never reports a rewrite' do
      described_class.open(['/a.rb']) { expect(it.rewritten).to be_empty }
    end
  end

  describe described_class::Ephemeral do
    it 'preserves the basename, which is what path-sensitive cops match on' do
      described_class.open(target_paths) do |workspace|
        expect(workspace.paths.map { File.basename(it) }).to contain_exactly('thing_spec.rb', 'thing.rb')
      end
    end

    it 'preserves the surrounding directories too' do
      described_class.open(target_paths) do |workspace|
        expect(workspace.paths).to all(include('/lib/'))
      end
    end

    it 'copies the contents' do
      described_class.open([spec_file.to_s]) do |workspace|
        expect(File.read(workspace.paths.fetch(0))).to eq("# spec\n")
      end
    end

    it 'maps a copy back to the corpus file it came from' do
      described_class.open([spec_file.to_s]) do |workspace|
        expect(workspace.original_for(workspace.paths.fetch(0))).to eq(spec_file.to_s)
      end
    end

    it 'returns nil for a path it never staged' do
      described_class.open([spec_file.to_s]) do |workspace|
        expect(workspace.original_for('/somewhere/else.rb')).to be_nil
      end
    end

    it 'reports nothing while the copies still match' do
      described_class.open(target_paths) { expect(it.rewritten).to be_empty }
    end

    it 'reports the copies that were rewritten, paired with their corpus file' do
      described_class.open(target_paths) do |workspace|
        rewritten_copy = workspace.paths.find { File.basename(it) == 'thing.rb' }
        File.write(rewritten_copy, "# corrected\n")

        expect(workspace.rewritten).to eq(rewritten_copy => plain_file.to_s)
      end
    end

    # The whole reason the copies exist.
    it 'leaves the corpus untouched even when the copies are rewritten', :aggregate_failures do
      described_class.open(target_paths) do |workspace|
        workspace.paths.each { File.write(it, "# clobbered\n") }
      end

      expect(spec_file.read).to eq("# spec\n")
      expect(plain_file.read).to eq("# plain\n")
    end

    it 'removes the copies once the block returns' do
      staged = described_class.open(target_paths) { it.paths.fetch(0) }

      expect(File.exist?(staged)).to be(false)
    end

    # One unreadable file in a thousand-file batch must not cost the whole batch.
    it 'drops a target it cannot stage rather than raising' do
      described_class.open([spec_file.to_s, corpus.join('missing.rb').to_s]) do |workspace|
        expect(workspace.paths.size).to eq(1)
      end
    end
  end

  describe 'staging a read-only corpus file' do
    it 'makes the copy writable so autocorrect can rewrite it' do
      source = corpus.join('readonly.rb').to_s
      File.write(source, "x = 1\n")
      File.chmod(0o444, source)

      described_class.open([source], autocorrect: true) do |workspace|
        copy = workspace.paths.first

        expect { File.write(copy, "y = 2\n") }.not_to raise_error
      end
    end
  end
end
