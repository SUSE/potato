class RepositoryService

  class RepositoryNotFound < RuntimeError
  end

  def create_repository!(product, url, attributes, custom: false)
    repository = Repository.find_or_initialize_by(external_url: url)

    # TODO: See if we can clean this up
    repository.attributes = attributes.select do |k, _|
      repository.attributes.keys.member?(k.to_s) && k.to_s != 'id'
    end
    repository.scc_id = attributes[:id] unless custom

    repository.external_url = url
    repository.local_path = Repository.make_local_path(url)

    ActiveRecord::Base.transaction do
      repository.save!
      attach_product!(product, repository) unless product.nil?
    end

    repository
  end

  def attach_product!(product, repository)
    product_service = find_product_service(product)
    RepositoriesServicesAssociation.find_or_create_by!(
      service_id: product_service.id,
      repository_id: repository.id
    )
  end

  def detach_product!(product, repository)
    product_service = find_product_service(product)
    association = RepositoriesServicesAssociation.find_by(
      service_id: product_service.id,
      repository_id: repository.id
    )
    association.destroy!
  end

  def change_mirroring_by_product!(mirroring_enabled, products)
    repo_count = 0
    products.each do |product|
      conditions = { mirroring_enabled: !mirroring_enabled } # to only update the repos which need change
      conditions[:enabled] = true if mirroring_enabled
      repo_count += product.change_repositories_mirroring!(conditions, mirroring_enabled)
    end

    repo_count
  end

  private

  def find_product_service(product)
    Service.find_or_create_by(product_id: product.id)
  end

end
