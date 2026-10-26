# frozen_string_literal: true

module Admin
  # Guías de la búsqueda con IA de coleccionables: los sitios para identificar
  # y de los que se aceptan precios, y los tipos de cambio con que el servidor
  # convierte esos precios.
  class CollectibleLookupSourcesController < ApplicationController
    before_action :authenticate_user!
    before_action :authorize_admin!
    before_action :set_source, only: %i[edit update destroy]

    # GET /admin/collectibles/lookup_sources
    def index
      @configured = Collectibles::LookupSource.configured?
      @sources = @configured ? Collectibles::LookupSource.ordered.to_a : Collectibles::LookupSource.in_use
      @rates = Collectibles::PriceConversion::CURRENCIES.index_with do |currency|
        SystemVariable.get(Collectibles::PriceConversion.variable_name(currency))
      end
    end

    # GET /admin/collectibles/lookup_sources/new
    def new
      @source = Collectibles::LookupSource.new(purpose: params[:purpose].presence_in(Collectibles::LookupSource.purposes.keys) || 'reference')
    end

    # GET /admin/collectibles/lookup_sources/:id/edit
    def edit; end

    # POST /admin/collectibles/lookup_sources
    def create
      @source = Collectibles::LookupSource.new(source_params)
      if @source.save
        redirect_to admin_collectible_lookup_sources_path, notice: "Sitio «#{@source.name}» agregado."
      else
        render :new, status: :unprocessable_entity
      end
    end

    # PATCH /admin/collectibles/lookup_sources/:id
    def update
      if @source.update(source_params)
        redirect_to admin_collectible_lookup_sources_path, notice: "Sitio «#{@source.name}» actualizado."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    # DELETE /admin/collectibles/lookup_sources/:id
    def destroy
      @source.destroy
      redirect_to admin_collectible_lookup_sources_path, notice: "Sitio «#{@source.name}» eliminado."
    end

    # POST /admin/collectibles/lookup_sources/install_defaults
    def install_defaults
      notice = if Collectibles::LookupSource.install_defaults!
                 'Sitios sugeridos guardados: ya puedes editarlos.'
               else
                 'Ya hay sitios guardados; no se cambió nada.'
               end
      redirect_to admin_collectible_lookup_sources_path, notice: notice
    end

    # PATCH /admin/collectibles/lookup_sources/rates
    # Vacío borra el tipo de cambio (esa moneda queda con el de la IA).
    def rates
      values = params.fetch(:rates, {}).permit(*Collectibles::PriceConversion::CURRENCIES).to_h
      invalid = values.reject { |_currency, value| value.blank? || value.to_s.tr(',', '.').to_f.positive? }.keys
      if invalid.any?
        return redirect_to admin_collectible_lookup_sources_path,
                           alert: "Tipo de cambio inválido para #{invalid.to_sentence}: usa un número mayor que cero."
      end

      values.each do |currency, value|
        SystemVariable.set(Collectibles::PriceConversion.variable_name(currency), value.to_s.strip.tr(',', '.'),
                           description: "Pesos mexicanos por 1 #{currency} (precios de la búsqueda con IA)")
      end
      redirect_to admin_collectible_lookup_sources_path, notice: 'Tipos de cambio guardados.'
    end

    private

    def set_source
      @source = Collectibles::LookupSource.find(params[:id])
    end

    def source_params
      params.expect(lookup_source: %i[name domain purpose category search_url notes active position])
    end
  end
end
