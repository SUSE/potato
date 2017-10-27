require 'rails_helper'

RSpec.describe RMT::CLI::Products do
  describe '#list' do
    let(:argv) { ['list'] }

    let(:expected_output) do
      rows = []
      rows << [
        product.id,
        product.name,
        product.version,
        product.arch,
        product.product_string,
        product.release_stage,
        product.mirror?,
        product.last_mirrored_at
      ]
      Terminal::Table.new(
        headings: ['ID', 'Name', 'Version', 'Architecture', 'Product string', 'Release stage', 'Mirror?', 'Last mirrored'],
        rows: rows
      ).to_s + "\n"
    end

    context 'with empty database' do
      subject(:command) { described_class.start(argv) }

      it 'stdout is empty' do
        expect { described_class.start(argv) }.to output('').to_stdout.and output(
          "No products found in the DB. Run \"rmt-cli scc sync\" to synchronize with your SUSE Customer Center data first.\n"
        ).to_stderr
      end
    end

    context 'with products' do
      let(:product) { FactoryGirl.create :product, :with_mirrored_repositories }

      before { product }

      it 'stdout contains products table' do
        expect { described_class.start(argv) }.to output(expected_output).to_stdout.and output('').to_stderr
      end
    end

    context 'with products and --release-stage parameter' do
      let(:argv) { ['list', '-r', 'released'] }
      let(:product) { FactoryGirl.create :product, :with_mirrored_repositories }
      let(:beta_product) { FactoryGirl.create :product, :with_mirrored_repositories, release_stage: 'beta' }

      before do
        product
        beta_product
      end

      it 'stdout contains products table' do
        expect { described_class.start(argv) }.to output(expected_output).to_stdout.and output('').to_stderr
      end
    end
  end

  describe '#enable' do
    let(:product) { FactoryGirl.create :product, :with_not_mirrored_repositories }
    let(:expected_output) { "#{product.repositories.where(enabled: true).count} repo(s) successfully enabled.\n" }

    before { expect { described_class.start(argv) }.to output(expected_output).to_stdout.and output('').to_stderr }

    context 'by product ID' do
      let(:argv) { ['enable', product.id.to_s] }

      it 'enables the mandatory product repositories' do
        product.repositories.each do |repository|
          expect(repository.mirroring_enabled).to eq(repository.enabled)
        end
      end
    end

    context 'by product string' do
      let(:argv) { ['enable', product.product_string] }

      it 'enables the mandatory product repositories' do
        product.repositories.each do |repository|
          expect(repository.mirroring_enabled).to eq(repository.enabled)
        end
      end
    end
  end

  describe '#disable' do
    let(:product) { FactoryGirl.create :product, :with_mirrored_repositories }
    let(:expected_output) { "#{product.repositories.count} repo(s) successfully disabled.\n" }

    before do
      expect { described_class.start(argv) }.to output(expected_output).to_stdout.and output('').to_stderr
    end

    context 'by product ID' do
      let(:argv) { ['disable', product.id.to_s] }

      it 'disabled the mandatory product repositories' do
        product.repositories.each do |repository|
          expect(repository.mirroring_enabled).to eq(false)
        end
      end
    end

    context 'by product string' do
      let(:argv) { ['disable', product.product_string] }

      it 'disabled the mandatory product repositories' do
        product.repositories.each do |repository|
          expect(repository.mirroring_enabled).to eq(false)
        end
      end
    end
  end
end
