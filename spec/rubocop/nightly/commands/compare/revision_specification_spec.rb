# frozen_string_literal: true

RSpec.describe RuboCop::Nightly::Commands::Compare::RevisionSpecification do
  describe '.parse' do
    def parse(specification, **) = described_class.parse(specification, **)

    context 'with a bare revision' do
      it 'resolves against the RuboCop repository', :aggregate_failures do
        result = parse('53e5d198f')

        expect(result.repository).to eq('https://github.com/rubocop/rubocop.git')
        expect(result.revision).to eq('53e5d198f')
      end

      it 'is rejected where only a repository makes sense' do
        expect { parse('53e5d198f', repository_only: true) }
          .to raise_error(ArgumentError, /not a repository URL/)
      end
    end

    # This used to fall through to the RuboCop repository because the discriminator was the
    # substring '.git:', which a plain URL does not contain.
    context 'with a repository URL and no revision' do
      it 'keeps the given repository', :aggregate_failures do
        result = parse('https://github.com/rails/rails.git', repository_only: true)

        expect(result.repository).to eq('https://github.com/rails/rails.git')
        expect(result.revision).to be_nil
      end

      it 'works without the .git suffix too' do
        expect(parse('https://github.com/rails/rails', repository_only: true).repository)
          .to eq('https://github.com/rails/rails')
      end
    end

    context 'with a repository URL and a revision' do
      it 'splits them', :aggregate_failures do
        result = parse('https://github.com/rails/rails.git:main')

        expect(result.repository).to eq('https://github.com/rails/rails.git')
        expect(result.revision).to eq('main')
      end
    end

    context 'with a port in the URL' do
      it 'does not mistake the port for a revision', :aggregate_failures do
        result = parse('https://git.example.com:8080/org/repo.git', repository_only: true)

        expect(result.repository).to eq('https://git.example.com:8080/org/repo.git')
        expect(result.revision).to be_nil
      end
    end

    context 'with an scp-style URL' do
      it 'does not crash and keeps the repository', :aggregate_failures do
        result = parse('git@github.com:rubocop/rubocop.git', repository_only: true)

        expect(result.repository).to eq('git@github.com:rubocop/rubocop.git')
        expect(result.revision).to be_nil
      end

      it 'still splits an explicit revision' do
        expect(parse('git@github.com:rubocop/rubocop.git:master').revision).to eq('master')
      end
    end
  end

  describe '#relative_path' do
    def path_for(url) = described_class.parse(url, repository_only: true).relative_path

    it 'uses the organisation and repository so different orgs do not collide' do
      expect(path_for('https://github.com/ruby/spec.git')).to eq('ruby/spec')
    end

    it 'handles scp-style URLs without raising' do
      expect(path_for('git@github.com:rubocop/rubocop.git')).to eq('rubocop/rubocop')
    end

    it 'never yields a traversal segment' do
      expect(path_for('https://example.com/../../etc/passwd')).not_to include('..')
    end
  end

  describe 'checkout naming' do
    it 'keys the checkout by revision so two revisions never share a directory' do
      from = described_class.parse('abc123')
      to = described_class.parse('master')

      expect(from.checkout_name).not_to eq(to.checkout_name)
    end

    it 'sanitises revisions that contain path separators' do
      expect(described_class.parse('feature/x').checkout_name).not_to include('/')
    end
  end
end
