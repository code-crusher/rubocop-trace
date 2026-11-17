# frozen_string_literal: true

RSpec.describe RuboCop::PendingCopsReporter do
  include FileHelper

  describe 'when pending cops exist', :isolated_environment do
    subject(:report_pending_cops) { described_class.warn_if_needed(config) }

    let(:config) { RuboCop::Config.new(parent_config) }

    before do
      create_empty_file('.rubocop.yml')

      # Setup similar to https://github.com/rubocop/rubocop-rspec/blob/master/lib/rubocop/rspec/inject.rb#L16
      # and https://github.com/runtastic/rt_rubocop_defaults/blob/master/lib/rt_rubocop_defaults/inject.rb#L21
      loader = RuboCop::ConfigLoader.configuration_from_file('.rubocop.yml')
      loader.instance_variable_set(:@default_configuration, config)
    end

    context 'when NewCops is set in a required file' do
      let(:parent_config) { { 'AllCops' => { 'NewCops' => 'enable' } } }

      it 'does not print a warning' do
        expect(described_class).not_to receive(:warn_on_pending_cops)
        report_pending_cops
      end
    end

    context 'when NewCops is not configured in a required file' do
      let(:parent_config) { { 'AllCops' => { 'Exclude:' => ['coverage/**/*'] } } }

      context 'when `pending_cops_only_qualified` returns empty array' do
        before do
          allow(described_class).to receive(:pending_cops_only_qualified).and_return([])
        end

        it 'does not print a warning' do
          expect(described_class).not_to receive(:warn_on_pending_cops)
          report_pending_cops
        end
      end

      context 'when `pending_cops_only_qualified` returns not empty array' do
        before do
          allow(described_class).to receive(:pending_cops_only_qualified).and_return(['Foo/Bar'])
        end

        it 'prints a warning' do
          expect(described_class).to receive(:warn_on_pending_cops)
          report_pending_cops
        end
      end

      context 'when printing the warning' do
        let(:parent_config) { { 'AllCops' => { 'Exclude:' => ['coverage/**/*'] } } }
        let(:pending_cop) { Struct.new(:name).new('Foo/Bar') }
        let(:pending_cops) { [pending_cop] }

        before do
          allow(described_class).to receive(:pending_cops_only_qualified).and_return(pending_cops)
        end

        # `spec/support/suppress_pending_warning.rb` replaces the reporting
        # method with a no-op suite-wide, so capture the arguments it receives
        # instead of the printed output.
        it 'summarizes pending cop names on a single line' do
          expect(described_class).to receive(:warn_on_pending_cops) do |cops|
            expect(cops).to contain_exactly(pending_cop)
          end

          report_pending_cops
        end

        context 'with multiple pending cops' do
          let(:pending_cops) do
            [Struct.new(:name).new('Foo/Bar'), Struct.new(:name).new('Foo/Baz')]
          end

          it 'reports every pending cop name' do
            expect(described_class).to receive(:warn_on_pending_cops) do |cops|
              expect(cops.map(&:name)).to eq(['Foo/Bar', 'Foo/Baz'])
            end

            report_pending_cops
          end
        end
      end
    end

    context 'when a department sets a version for NewCops in a required file' do
      let(:parent_config) do
        {
          'Lint' => { 'NewCops' => '0.90' },
          'Lint/BooleanSymbol' => { 'Enabled' => 'pending', 'VersionAdded' => '0.90' },
          'Lint/DuplicateBranch' => { 'Enabled' => 'pending', 'VersionAdded' => '1.3' }
        }
      end

      it 'prints a warning only for cops added after the version' do
        expect(described_class).to receive(:warn_on_pending_cops) do |pending_cops|
          expect(pending_cops.map(&:name)).to eq(['Lint/DuplicateBranch'])
        end
        report_pending_cops
      end
    end

    context 'when a department sets `NewCops: pending` and `AllCops` sets `NewCops: enable` in a required file' do
      let(:parent_config) do
        {
          'AllCops' => { 'NewCops' => 'enable' },
          'Lint' => { 'NewCops' => 'pending' },
          'Lint/BooleanSymbol' => { 'Enabled' => 'pending', 'VersionAdded' => '0.90' }
        }
      end

      it 'prints a warning for the cops of the department' do
        expect(described_class).to receive(:warn_on_pending_cops) do |pending_cops|
          expect(pending_cops.map(&:name)).to eq(['Lint/BooleanSymbol'])
        end
        report_pending_cops
      end
    end
  end
end
