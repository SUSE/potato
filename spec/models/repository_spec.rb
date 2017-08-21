require 'rails_helper'

RSpec.describe Repository, type: :model do
  subject { build(:repository) }

  let(:product) { create(:product, :with_mirrored_repositories) }

  it { is_expected.to have_many :products }
  it { is_expected.to have_many :services }
  it { is_expected.to have_many :systems }
  it { is_expected.to have_many :repositories_services_associations }

  it { is_expected.to validate_presence_of(:name) }
  it { is_expected.to validate_presence_of(:external_url) }

  it { is_expected.to have_db_column(:name).of_type(:string).with_options(null: false) }
  it { is_expected.to have_db_column(:external_url).of_type(:string).with_options(null: false) }

  describe '.make_local_path' do
    subject { described_class.make_local_path(url) }

    context 'old SLES repo' do
      let(:url) { 'https://updates.suse.com/repo/$RCE/SLES11-Pool/sle-11-x86_64/' }

      it { is_expected.to eq('/$RCE/SLES11-Pool/sle-11-x86_64/') }
    end

    context 'new SLES repo' do
      let(:url) { 'https://updates.suse.com/SUSE/Products/SLE-SERVER/12-SP2/x86_64/product/' }

      it { is_expected.to eq('/SUSE/Products/SLE-SERVER/12-SP2/x86_64/product/') }
    end

    context 'generic repo that starts with "/repo"' do
      let(:url) { 'https://example.com/repo/dummy_repo/' }

      it { is_expected.to eq('/repo/dummy_repo/') }
    end
  end
end
