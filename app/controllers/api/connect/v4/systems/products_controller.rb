class Api::Connect::V4::Systems::ProductsController < Api::Connect::V3::Systems::ProductsController

  def destroy
    if @product.product_type == 'base'
      untranslated = N_('The product "%s" is a base product and cannot be deactivated')
      respond_with_error message: (untranslated % @product.name), localized_message: (_(untranslated) % @product.name)
    elsif @system.activations.joins(:product).where(products: { id: @product.extension_ids }).any?
      untranslated = N_('Cannot deactivate the product "%s". Other activated products depend upon it.')
      respond_with_error message: (untranslated % @product.name), localized_message: (_(untranslated) % @product.name)
    else
      @activation = Activation.find_by!(
        system_id: @system.id,
        service_id: @product.service.id
      )
      @activation.destroy
      logger.info(sprintf(N_('Product "%s" deactivated'), @product.friendly_name))
      render_service
    end
  rescue ActiveRecord::RecordNotFound
    untranslated = N_('%s is not yet activated on the system.')
    respond_with_error message: (untranslated % @product.name), localized_message: (_(untranslated) % @product.name)
  end

end
