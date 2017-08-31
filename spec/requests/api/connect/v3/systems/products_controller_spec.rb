require 'rails_helper'

RSpec.describe Api::Connect::V3::Systems::ProductsController do
  include_context 'auth header', :system, :login, :password
  include_context 'version header', 3

  let(:url) { connect_systems_products_url }
  let(:headers) { auth_header.merge(version_header) }
  let(:system) { FactoryGirl.create(:system) }
  let(:product_with_repos) { FactoryGirl.create(:product, :with_mirrored_repositories) }
  let(:product_not_mirrored) { FactoryGirl.create(:product, :with_not_mirrored_repositories) }

  describe '#activate' do
    it_behaves_like 'products controller action' do
      let(:verb) { 'post' }
    end

    context 'when product mandatory repos aren\'t mirrored' do
      subject { response }

      let(:payload) do
        {
          identifier: product_not_mirrored.identifier,
          version: product_not_mirrored.version,
          arch: product_not_mirrored.arch
        }
      end

      let(:error_json) do
        {
          'type' => 'error',
          'error' => "Not all mandatory repositories are mirrored for product #{product_not_mirrored.friendly_name}",
          'localized_error' => "Not all mandatory repositories are mirrored for product #{product_not_mirrored.friendly_name}"
        }.to_json
      end

      before { post url, headers: headers, params: payload }
      its(:code) { is_expected.to eq('422') }
      its(:body) { is_expected.to eq(error_json) }
    end

    context 'when product has repos' do
      subject { response }

      let(:payload) do
        {
          identifier: product_with_repos.identifier,
          version: product_with_repos.version,
          arch: product_with_repos.arch
        }
      end
      let(:serialized_json) do
        V3::ServiceSerializer.new(
          product_with_repos.service,
          base_url: URI::HTTP.build({ scheme: response.request.scheme, host: response.request.host }).to_s
        ).to_json
      end

      before { post url, headers: headers, params: payload }
      its(:code) { is_expected.to eq('201') }
      its(:body) { is_expected.to eq(serialized_json) }

      describe 'JSON response' do
        subject { JSON.parse(response.body, symbolize_names: true) }

        it { is_expected.to include :id, :name, :product, :url, :obsoleted_service_name }
      end
    end
  end

  describe '#show' do
    let(:activation) { FactoryGirl.create(:activation, :with_mirrored_product) }

    it_behaves_like 'products controller action' do
      let(:verb) { 'get' }
    end

    context 'when product is not activated' do
      subject { response }

      let(:payload) do
        {
          identifier: product_with_repos.identifier,
          version: product_with_repos.version,
          arch: product_with_repos.arch
        }
      end

      before { get url, headers: headers, params: payload }
      its(:code) { is_expected.to eq('422') }

      describe 'JSON response' do
        subject { JSON.parse(response.body, symbolize_names: true) }

        its([:error]) { is_expected.to match(/The requested product '.*' is not activated on this system/) }
      end
    end

    context 'when product is activated' do
      subject { response }

      let(:system) { activation.system }
      let(:payload) do
        {
          identifier: activation.product.identifier,
          version: activation.product.version,
          arch: activation.product.arch
        }
      end
      let(:serialized_json) do
        V3::ProductSerializer.new(
          activation.service.product,
          base_url: URI::HTTP.build({ scheme: response.request.scheme, host: response.request.host }).to_s
        ).to_json
      end

      before { get url, headers: headers, params: payload }
      its(:code) { is_expected.to eq('200') }
      its(:body) { is_expected.to eq(serialized_json) }
    end
  end

  describe '#upgrade' do
    it_behaves_like 'products controller action' do
      let(:verb) { 'put' }
    end

    before { put url, headers: headers, params: payload }
    subject { response }

    context 'with not activated product' do
      let(:product) { FactoryGirl.create(:product, :with_mirrored_repositories) }
      let(:payload) do
        {
          identifier: product.identifier,
          version: product.version,
          arch: product.arch
        }
      end

      let(:error_response) do
        {
          type: 'error',
          error: "No activation with product '#{product.friendly_name}' was found.",
          localized_error: "No activation with product '#{product.friendly_name}' was found."
        }
      end


      its(:code) { is_expected.to eq('422') }
      its(:body) { is_expected.to eq(error_response.to_json) }
    end

    context 'with activated product' do
      let(:old_product) { FactoryGirl.create(:product, :with_mirrored_repositories, :activated, system: system) }
      let(:new_product) { FactoryGirl.create(:product, :with_mirrored_repositories, predecessor: old_product) }
      let!(:activation_id) { system.activations.first.id }

      let(:payload) do
        {
          identifier: new_product.identifier,
          version: new_product.version,
          arch: new_product.arch
        }
      end

      let(:serialized_json) do
        V3::ServiceSerializer.new(
          new_product.service,
          base_url: URI::HTTP.build({ scheme: response.request.scheme, host: response.request.host }).to_s
        ).to_json
      end

      its(:code) { is_expected.to eq('201') }
      its(:body) { is_expected.to eq(serialized_json) }
      it 'updates the activation' do
        activation = Activation.find(activation_id)

        expect(activation.product.id).to eq(new_product.id)
      end
    end
  end

  describe '#migrations' do
    before { post url, headers: headers, params: payload }
    subject { response }

    let(:url) { connect_systems_products_migrations_url }

    context 'without installed_products' do
      let(:payload) { {} }
      let(:error_response) do
        {
          type: 'error',
          error: 'Required parameters are missing or empty: installed_products',
          localized_error: 'Required parameters are missing or empty: installed_products'
        }.to_json
      end

      its(:code) { is_expected.to eq('422') }
      its(:body) { is_expected.to eq(error_response) }
    end

    context 'with no base product in installed_products' do
      let(:payload) do
        { 'installed_products': [ { 'identifier': 'non_existent_product', 'version': '42', 'arch': 'x86_64', 'release_type': nil } ] }
      end
      let(:error_response) do
        { type: 'error', error: 'No base product found.', localized_error: 'No base product found.' }.to_json
      end

      its(:code) { is_expected.to eq('422') }
      its(:body) { is_expected.to eq(error_response) }
    end

    context 'with not activated product in installed_products' do
      let(:product) { FactoryGirl.create(:product, :with_mirrored_repositories, product_type: 'base') }
      let(:payload) do
        {
          'installed_products': [
            { 'identifier': product.identifier, 'version': product.version, 'arch': product.arch, 'release_type': product.release_type }
          ]
        }
      end
      let(:error_response) do
        {
          type: 'error',
          error: "The requested products '#{product.friendly_name}' are not activated on the system.",
          localized_error: "The requested products '#{product.friendly_name}' are not activated on the system."
        }.to_json
      end

      its(:code) { is_expected.to eq('422') }
      its(:body) { is_expected.to eq(error_response) }
    end

    context 'with multiple base products in installed_products' do
      let(:first_product) { FactoryGirl.create(:product, :with_mirrored_repositories, :activated, system: system, product_type: 'base') }
      let(:second_product) { FactoryGirl.create(:product, :with_mirrored_repositories, :activated, system: system, product_type: 'base') }
      let(:payload) do
        {
          'installed_products': [
            {
              'identifier': first_product.identifier,
              'version': first_product.version,
              'arch': first_product.arch,
              'release_type': first_product.release_type
            },
            {
              'identifier': second_product.identifier,
              'version': second_product.version,
              'arch': second_product.arch,
              'release_type': second_product.release_type
            }
          ]
        }
      end
      let(:error_response) do
        {
          type: 'error',
          error: "Multiple base products found: '#{first_product.friendly_name}, #{second_product.friendly_name}'.",
          localized_error: "Multiple base products found: '#{first_product.friendly_name}, #{second_product.friendly_name}'."
        }.to_json
      end

      its(:code) { is_expected.to eq('422') }
      its(:body) { is_expected.to eq(error_response) }
    end

    context 'with a proper set of products in installed_products' do
      let(:first_product) { FactoryGirl.create(:product, :with_mirrored_repositories, :activated, system: system, product_type: 'base') }
      let(:second_product) do
        FactoryGirl.create(
          :product,
          :with_mirrored_repositories,
          product_type: 'base',
          predecessor: first_product
        )
      end
      let(:payload) do
        product = second_product.predecessors.first # For initializing everything in the correct order
        {
          'installed_products': [ {
            'identifier': product.identifier,
            'version': product.version,
            'arch': product.arch,
            'release_type': product.release_type
          } ]
        }
      end
      let(:expected_response) do
        [[::V3::UpgradePathItemSerializer.new(second_product)]].to_json
      end

      its(:code) { is_expected.to eq('200') }
      its(:body) do
        is_expected.to eq(expected_response)
      end
    end
  end
end
