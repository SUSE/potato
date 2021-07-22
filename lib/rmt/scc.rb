require 'rmt/config'
require 'rmt/logger'
require 'suse/connect/api'

class RMT::SCC
  class CredentialsError < RuntimeError; end
  class DataFilesError < RuntimeError; end

  def initialize(options = {})
    @logger = RMT::Logger.new(STDOUT)
    debug = options[:debug] || Settings&.log_level&.cli == 'debug'
    @logger.level = debug ? Logger::DEBUG : Logger::INFO
  end

  def sync
    credentials_set? || (raise CredentialsError, _('SCC credentials not set.'))

    @logger.info(_('Downloading data from SCC'))
    scc_api_client = SUSE::Connect::Api.new(Settings.scc.username, Settings.scc.password)

    @logger.info(_('Updating products'))
    data = scc_api_client.list_products
    data.each { |item| create_product(item) }
    data.each { |item| migration_paths(item) }

    update_repositories(scc_api_client.list_repositories)

    Repository.remove_suse_repos_without_tokens!

    update_subscriptions(scc_api_client.list_subscriptions)
  end

  def export(path)
    credentials_set? || (raise CredentialsError, 'SCC credentials not set.')

    @logger.info _('Exporting data from SCC to %{path}') % { path: path }

    scc_api_client = SUSE::Connect::Api.new(Settings.scc.username, Settings.scc.password)

    @logger.info(_('Exporting products'))
    File.write(File.join(path, 'organizations_products.json'), scc_api_client.list_products.to_json)
    # For SUMA, we also export the unscoped products with the filename it expects.
    File.write(File.join(path, 'organizations_products_unscoped.json'), scc_api_client.list_products_unscoped.to_json)

    @logger.info(_('Exporting repositories'))
    File.write(File.join(path, 'organizations_repositories.json'), scc_api_client.list_repositories.to_json)

    @logger.info(_('Exporting subscriptions'))
    File.write(File.join(path, 'organizations_subscriptions.json'), scc_api_client.list_subscriptions.to_json)

    @logger.info(_('Exporting orders'))
    File.write(File.join(path, 'organizations_orders.json'), scc_api_client.list_orders.to_json)
  end

  def import(path)
    missing_files = %w[products repositories subscriptions]
      .map { |data| "organizations_#{data}.json" }
      .reject { |filename| File.exist?(File.join(path, filename)) }
    raise DataFilesError, _('Missing data files: %{files}') % { files: missing_files.join(', ') } if missing_files.any?

    @logger.info _('Importing SCC data from %{path}') % { path: path }

    @logger.info _('Updating products')
    data = JSON.parse(File.read(File.join(path, 'organizations_products.json')), symbolize_names: true)
    data.each do |item|
      create_product(item)
    end
    data.each { |item| migration_paths(item) }

    update_repositories(JSON.parse(File.read(File.join(path, 'organizations_repositories.json')), symbolize_names: true))

    Repository.remove_suse_repos_without_tokens!

    update_subscriptions(JSON.parse(File.read(File.join(path, 'organizations_subscriptions.json')), symbolize_names: true))
  end

  def sync_systems
    unless Settings.scc.sync_systems
      @logger.warn _('Syncing systems to SCC is disabled by the configuration file, exiting.')
      return
    end

    credentials_set? || (raise CredentialsError, _('SCC credentials not set.'))
    scc_api_client = SUSE::Connect::Api.new(Settings.scc.username, Settings.scc.password)

    System.where(scc_registered_at: nil).find_in_batches(batch_size: 20) do |batch|
      batch.each do |system|
        @logger.info(_('Syncing system %{login} to SCC') % { login: system.login })
        response = scc_api_client.forward_system_activations(system)
        # Update attributes without triggering after_update callback (which resets scc_registered_at to nil)
        system.update_columns(scc_system_id: response[:id], scc_registered_at: Time.current)
      rescue SUSE::Connect::Api::RequestError => e
        @logger.error(_('Failed to sync system %{login}: %{error}') % { login: system.login, error: e.to_s })
      end
    end

    DeregisteredSystem.find_in_batches(batch_size: 20) do |batch|
      batch.each do |deregistered_system|
        @logger.info(
          _('Syncing de-registered system %{scc_system_id} to SCC') % {
            scc_system_id: deregistered_system.scc_system_id
          }
        )
        scc_api_client.forward_system_deregistration(deregistered_system.scc_system_id)
        deregistered_system.destroy!
      end
    end
  end

  protected

  def credentials_set?
    Settings.try(:scc).try(:username) && Settings.try(:scc).try(:password)
  end

  def update_repositories(repos)
    @logger.info _('Updating repositories')
    repos.each do |item|
      update_auth_token_enabled_attr(item)
    end
  end

  def update_subscriptions(subscriptions)
    @logger.info _('Updating subscriptions')
    Subscription.delete_all
    subscriptions.each do |item|
      create_subscription(item)
    end
  end

  def get_product(id)
    Product.find_or_create_by(id: id)
  end

  def create_product(item, root_product_id = nil, base_product = nil, recommended = false, migration_extra = false)
    ActiveRecord::Base.transaction do
      @logger.debug _('Adding product %{product}') % { product: "#{item[:identifier]}/#{item[:version]}#{(item[:arch]) ? '/' + item[:arch] : ''}" }

      product = get_product(item[:id])
      product.attributes = item.select { |k, _| product.attributes.keys.member?(k.to_s) }
      product.save!

      create_service(item, product)

      if root_product_id
        ProductsExtensionsAssociation.create(
          product_id: base_product,
          extension_id: product.id,
          root_product_id: root_product_id,
          recommended: recommended,
          migration_extra: migration_extra
        )
      else
        root_product_id = product.id
        ProductsExtensionsAssociation.where(root_product_id: root_product_id).destroy_all
      end

      item[:extensions].each do |ext_item|
        create_product(ext_item, root_product_id, product.id, ext_item[:recommended], ext_item[:migration_extra])
      end
    end
  end

  def create_service(item, product)
    product.create_service!
    item[:repositories].each do |repo_item|
      repository_service.create_repository!(product, repo_item[:url], repo_item)
    end
  end

  def update_auth_token_enabled_attr(item)
    uri = URI(item[:url])
    auth_token = uri.query

    Repository.find_by!(scc_id: item[:id]).update! auth_token: auth_token, enabled: item[:enabled]
  end

  def create_subscription(item)
    subscription = Subscription.new
    subscription.attributes = item.select { |k, _| subscription.attributes.keys.member?(k.to_s) }
    subscription.kind = item[:type]
    subscription.save!

    item[:product_classes].each do |item_class|
      subscription_product_class = SubscriptionProductClass.new
      subscription_product_class.subscription_id = subscription.id
      subscription_product_class.product_class = item_class
      subscription_product_class.save!
    end
  end

  def migration_paths(item)
    product = get_product(item[:id])
    ProductPredecessorAssociation.where(product_id: product.id).destroy_all
    create_migration_path(product, item[:online_predecessor_ids], :online) unless item[:online_predecessor_ids].empty?
    create_migration_path(product, item[:offline_predecessor_ids], :offline) unless item[:offline_predecessor_ids].empty?
    item[:extensions].each do |ext_item|
      migration_paths(ext_item)
    end
  end

  def create_migration_path(product, predecessors, kind)
    predecessors.each do |predecessor_id|
      ProductPredecessorAssociation.create(product_id: product.id, predecessor_id: predecessor_id, kind: kind) unless Product.find_by(id: predecessor_id).nil?
    end
  end

  private

  def repository_service
    @repository_service ||= RepositoryService.new
  end

end
