# frozen_string_literal: true

RSpec.describe RuboCop::Nightly::Configuration::DependenciesMiner do
  let(:data_home) { Dir.mktmpdir('rubocop-nightly-miner') }
  let(:gems_root) do
    RuboCop::Nightly::Runtime.gems_data_directory.join("ruby/#{ruby_abi}/bundler/gems/rubocop-abc1234/lib/rubocop/cop")
  end
  let(:ruby_abi) { '3.4.0' }

  around do |example|
    with_environment_variable('XDG_DATA_HOME', data_home, &example)
  ensure
    FileUtils.remove_entry(data_home)
  end

  def write_cop(relative_path, source)
    path = gems_root.join(relative_path)
    FileUtils.mkdir_p(path.dirname)
    File.write(path, source)
  end

  describe '#mine' do
    it 'maps a cop file to its real cop name' do
      write_cop('metrics/abc_size.rb', "class AbcSize < Base\n  'Metrics/MethodLength'\nend")

      expect(described_class.new(%w[Metrics/AbcSize Metrics/MethodLength]).mine)
        .to eq('Metrics/AbcSize' => Set['Metrics/MethodLength'])
    end

    it 'handles RSpec cop names without mangling every lowercase s' do
      write_cop('rspec/message_spies.rb', "class MessageSpies < Base\n  'RSpec/DescribedClass'\nend")

      expect(described_class.new(%w[RSpec/MessageSpies RSpec/DescribedClass]).mine.keys)
        .to eq(['RSpec/MessageSpies'])
    end

    it 'handles acronym cop names' do
      write_cop('gemspec/require_mfa.rb', "class RequireMFA < Base\n  'Gemspec/DuplicatedAssignment'\nend")

      expect(described_class.new(%w[Gemspec/RequireMFA Gemspec/DuplicatedAssignment]).mine.keys)
        .to eq(['Gemspec/RequireMFA'])
    end

    it 'handles multi-word departments' do
      write_cop('factory_bot/create_list.rb', "class CreateList < Base\n  'FactoryBot/AttributeDefinedStatically'\nend")

      expect(described_class.new(%w[FactoryBot/CreateList FactoryBot/AttributeDefinedStatically]).mine.keys)
        .to eq(['FactoryBot/CreateList'])
    end

    it 'handles nested department directories' do
      write_cop('rspec/capybara/specific_matcher.rb', "class SpecificMatcher < Base\n  'RSpec/DescribedClass'\nend")

      expect(described_class.new(%w[RSpec/Capybara/SpecificMatcher RSpec/DescribedClass]).mine.keys)
        .to eq(['RSpec/Capybara/SpecificMatcher'])
    end

    it 'finds cops that do not literally inherit from `Base`' do
      write_cop('style/thing.rb', "class Thing < ::RuboCop::Cop::Base\n  'Style/Other'\nend")

      expect(described_class.new(%w[Style/Thing Style/Other]).mine.keys).to eq(['Style/Thing'])
    end

    it 'ignores files that are not cops' do
      write_cop('mixin/helper.rb', "module Helper\n  'Style/Other'\nend")

      expect(described_class.new(%w[Style/Other]).mine).to be_empty
    end

    it 'picks up dependencies expressed in an included mixin' do
      write_cop('mixin/alignment.rb', "module Alignment\n  'Layout/IndentationWidth'\nend")
      write_cop('layout/end_alignment.rb', "class EndAlignment < Base\n  include Alignment\nend")

      expect(described_class.new(%w[Layout/EndAlignment Layout/IndentationWidth]).mine)
        .to eq('Layout/EndAlignment' => Set['Layout/IndentationWidth'])
    end

    it 'never lists a cop as its own dependency' do
      write_cop('style/thing.rb', "class Thing < Base\n  'Style/Thing'\nend")

      expect(described_class.new(%w[Style/Thing]).mine).to be_empty
    end

    context 'when the gems were installed under a different ruby ABI' do
      let(:ruby_abi) { '4.0.0' }

      it 'still finds the cop sources' do
        write_cop('metrics/abc_size.rb', "class AbcSize < Base\n  'Metrics/MethodLength'\nend")

        expect(described_class.new(%w[Metrics/AbcSize Metrics/MethodLength]).mine).not_to be_empty
      end
    end

    context 'when nothing is installed' do
      it 'warns rather than silently returning an empty map', :aggregate_failures do
        allow(RuboCop::Nightly.logger).to receive(:warn)

        expect(described_class.new(%w[Style/Thing]).mine).to be_empty
        expect(RuboCop::Nightly.logger).to have_received(:warn).with(/gems:install/)
      end
    end
  end
end
