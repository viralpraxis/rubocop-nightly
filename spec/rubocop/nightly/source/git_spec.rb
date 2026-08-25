# frozen_string_literal: true

RSpec.describe RuboCop::Nightly::Source::Git do
  describe '#fetch' do
    it 'rejects entries that are not mappings with a url' do
      expect { described_class.new(sources: ['https://example.com/x.git']).fetch }
        .to raise_error(RuboCop::Nightly::ConfigurationError, /'url' key/)
    end

    it 'skips a repository it cannot clone rather than returning a path that does not exist' do
      allow(RuboCop::Nightly.logger).to receive(:error)
      source = described_class.new(sources: [{ 'url' => 'https://example.invalid/nope.git', 'branch' => 'main' }])

      expect(source.fetch).to be_empty
    end
  end

  describe 'directory naming' do
    def name_for(url) = described_class.new(sources: []).send(:directory_name_for, url)

    it 'strips the .git suffix' do
      expect(name_for('https://github.com/jekyll/jekyll.git')).to eq('github.com_jekyll_jekyll')
    end

    it 'does not collide across organisations', :aggregate_failures do
      expect(name_for('https://github.com/ruby/spec.git')).not_to eq(name_for('https://github.com/rspec/spec.git'))
    end

    it 'never escapes the data directory' do
      expect(name_for('https://example.com/../../etc/passwd')).not_to include('..')
    end
  end
end
