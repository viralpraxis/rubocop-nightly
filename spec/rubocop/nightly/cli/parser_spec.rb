# frozen_string_literal: true

RSpec.describe RuboCop::Nightly::CLI::Parser do
  def parse(*arguments) = described_class.parse(arguments)

  describe '.parse' do
    it 'reads the subcommand from its argument, not the global ARGV' do
      expect(parse('fuzzer', '--source', 'rubygems').source).to eq('rubygems')
    end

    it 'does not mutate the arguments it is given' do
      arguments = %w[fuzzer --source rubygems]

      expect { described_class.parse(arguments) }.not_to change(arguments, :size)
    end

    it 'does not mutate the global ARGV' do
      expect { parse('fuzzer', '--source', 'rubygems') }.not_to change(ARGV, :size)
    end

    context 'with no arguments' do
      it 'returns usage instead of raising' do
        expect(described_class.parse([]).command).to eq(:help)
      end
    end

    %w[help --help -h].each do |flag|
      it "treats #{flag} as a help request" do
        expect(parse(flag).command).to eq(:help)
      end
    end

    %w[version --version -v].each do |flag|
      it "treats #{flag} as a version request" do
        expect(parse(flag).command).to eq(:version)
      end
    end

    it 'reports unknown commands with usage' do
      expect { parse('nope') }.to raise_error(RuboCop::Nightly::CLI::UsageError, /unknown command.*Usage/m)
    end

    describe 'fuzzer' do
      it 'requires a source' do
        expect { parse('fuzzer') }.to raise_error(RuboCop::Nightly::CLI::UsageError, /--source/)
      end

      it 'rejects an unknown source' do
        expect { parse('fuzzer', '--source', 'nope') }
          .to raise_error(RuboCop::Nightly::CLI::UsageError, /unknown source/)
      end

      it 'rejects a non-positive batch size' do
        expect { parse('fuzzer', '--source', 'rubygems', '--batch-size', '0') }
          .to raise_error(RuboCop::Nightly::CLI::UsageError, /--batch-size/)
      end

      it 'rejects a non-positive batch timeout' do
        expect { parse('fuzzer', '--source', 'rubygems', '--batch-timeout', '-1') }
          .to raise_error(RuboCop::Nightly::CLI::UsageError, /--batch-timeout/)
      end

      it 'rejects an unknown log level' do
        expect { parse('fuzzer', '--source', 'rubygems', '--log-level', 'LOUD') }
          .to raise_error(RuboCop::Nightly::CLI::UsageError, /--log-level/)
      end

      it 'defaults the batch size' do
        expect(parse('fuzzer', '--source', 'rubygems').batch_size).to eq(1000)
      end

      it 'does not reduce by default' do
        expect(parse('fuzzer', '--source', 'rubygems').reduce).to be(false)
      end

      it 'enables reduction with --reduce' do
        expect(parse('fuzzer', '--source', 'rubygems', '--reduce').reduce).to be(true)
      end

      it 'accepts an explicit --no-reduce' do
        expect(parse('fuzzer', '--source', 'rubygems', '--no-reduce').reduce).to be(false)
      end

      it 'passes the choice through to the executor' do
        expect(parse('fuzzer', '--source', 'rubygems', '--reduce').executor_options).to include(reduce: true)
      end

      it 'accepts --batch-timeout on both its short and long form', :aggregate_failures do
        expect(parse('fuzzer', '--source', 'rubygems', '-t', '5').batch_timeout).to eq(5)
        expect(parse('fuzzer', '--source', 'rubygems', '--batch-timeout', '5').batch_timeout).to eq(5)
      end

      it 'requires --mirror-path for the mirror source' do
        expect { parse('fuzzer', '--source', 'mirror') }
          .to raise_error(RuboCop::Nightly::CLI::UsageError, /--mirror-path/)
      end

      it 'requires --git-sources for the git source' do
        expect { parse('fuzzer', '--source', 'git') }
          .to raise_error(RuboCop::Nightly::CLI::UsageError, /--git-sources/)
      end
    end

    describe 'fuzzer --git-sources' do
      def parse_with(contents)
        Tempfile.create(['sources', '.yml']) do |file|
          file.write(contents)
          file.flush

          return parse('fuzzer', '--source', 'git', '--git-sources', file.path)
        end
      end

      it 'reports a missing file as a usage error' do
        expect { parse('fuzzer', '--source', 'git', '--git-sources', '/nope.yml') }
          .to raise_error(RuboCop::Nightly::CLI::UsageError, /file not found/)
      end

      it 'rejects a YAML document that is not a list of mappings' do
        expect { parse_with("just a string\n") }
          .to raise_error(RuboCop::Nightly::CLI::UsageError, /list of mappings/)
      end

      it 'rejects entries without a url' do
        expect { parse_with("- branch: main\n") }
          .to raise_error(RuboCop::Nightly::CLI::UsageError, /'url' key/)
      end

      it 'rejects malformed YAML' do
        expect { parse_with("- url: [\n") }
          .to raise_error(RuboCop::Nightly::CLI::UsageError, /not valid YAML/)
      end

      it 'loads a valid file' do
        options = parse_with("- url: https://example.com/x.git\n  branch: main\n")

        expect(options.source_options)
          .to eq(sources: [{ 'url' => 'https://example.com/x.git', 'branch' => 'main' }])
      end
    end

    describe 'fuzzer --rubygems-limit' do
      it 'is absent from the source options by default' do
        expect(parse('fuzzer', '--source', 'rubygems').source_options).to eq({})
      end

      it 'is handed to the rubygems source' do
        expect(parse('fuzzer', '--source', 'rubygems', '--rubygems-limit', '20').source_options)
          .to eq(limit: 20)
      end

      it 'rejects a non-positive limit' do
        expect { parse('fuzzer', '--source', 'rubygems', '--rubygems-limit', '0') }
          .to raise_error(RuboCop::Nightly::CLI::UsageError, /--rubygems-limit must be a positive integer/)
      end
    end

    describe 'reduction' do
      it 'is off by default' do
        expect(parse('fuzzer', '--source', 'rubygems').reduce).to be(false)
      end

      it 'is enabled by --reduce' do
        expect(parse('fuzzer', '--source', 'rubygems', '--reduce').reduce).to be(true)
      end

      it 'is disabled by --no-reduce' do
        expect(parse('fuzzer', '--source', 'rubygems', '--no-reduce').reduce).to be(false)
      end
    end

    describe 'compare' do
      it 'requires --from, --to and --source', :aggregate_failures do
        expect { parse('compare') }.to raise_error(RuboCop::Nightly::CLI::UsageError, /--from/)
        expect { parse('compare', '--from', 'a') }.to raise_error(RuboCop::Nightly::CLI::UsageError, /--to/)
        expect { parse('compare', '--from', 'a', '--to', 'b') }
          .to raise_error(RuboCop::Nightly::CLI::UsageError, /--source/)
      end

      it 'builds compare options' do
        options = parse('compare', '--from', 'a', '--to', 'b', '--source', 'https://example.com/x.git')

        expect(options).to have_attributes(command: :compare, from: 'a', to: 'b')
      end
    end
  end
end
