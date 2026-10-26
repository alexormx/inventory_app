# frozen_string_literal: true

module Collectibles
  # Una guía de la búsqueda con IA: un sitio para identificar la pieza (fecha,
  # rareza) o del que se aceptan precios en México o en el mundo. Se editan en
  # el admin (Coleccionables › Guías de búsqueda). Con `search_url` también sale
  # en el resultado como enlace para buscar a mano.
  #
  # Mientras no se haya guardado ninguna, se usan las sugeridas (DEFAULTS): la
  # búsqueda funciona igual recién instalada y el admin las guarda con un clic
  # para empezar a editarlas.
  class LookupSource < ApplicationRecord
    self.table_name = 'collectible_lookup_sources'

    PURPOSE_LABELS = {
      'reference' => 'Identificar, fecha y rareza',
      'prices_mx' => 'Precios en México (MXN)',
      'prices_world' => 'Precios en el mundo (USD)'
    }.freeze
    QUERY = '{q}'
    NAME_MAX = 60
    NOTES_MAX = 300
    URL_MAX = 500
    DOMAIN_FORMAT = /\A[a-z0-9-]+(\.[a-z0-9-]+)+\z/

    DEFAULTS = [
      { name: 'hobbyDB', domain: 'hobbydb.com', purpose: 'reference',
        search_url: 'https://www.google.com/search?q=site%3Ahobbydb.com+{q}',
        notes: 'Catálogo de coleccionistas: variantes, año y tiraje.' },
      { name: 'Hot Wheels Wiki', domain: 'hotwheels.fandom.com', purpose: 'reference',
        search_url: 'https://hotwheels.fandom.com/wiki/Special:Search?query={q}',
        notes: 'Series, años y variantes de Hot Wheels.' },
      { name: 'Takara Tomy (Tomica)', domain: 'takaratomy.co.jp', purpose: 'reference',
        search_url: 'https://www.google.com/search?q=site%3Atakaratomy.co.jp+{q}',
        notes: 'Fabricante de Tomica: fecha de lanzamiento oficial.' },
      { name: 'Mercado Libre', domain: 'mercadolibre.com.mx', purpose: 'prices_mx',
        search_url: 'https://listado.mercadolibre.com.mx/{q}' },
      { name: 'Amazon México', domain: 'amazon.com.mx', purpose: 'prices_mx',
        search_url: 'https://www.amazon.com.mx/s?k={q}' },
      { name: 'eBay (vendidos)', domain: 'ebay.com', purpose: 'prices_world',
        search_url: 'https://www.ebay.com/sch/i.html?_nkw={q}&LH_Sold=1&LH_Complete=1',
        notes: 'Prefiere anuncios vendidos (Sold): son el precio real.' },
      { name: 'Amazon EE. UU.', domain: 'amazon.com', purpose: 'prices_world',
        search_url: 'https://www.amazon.com/s?k={q}' },
      { name: 'Amazon Japón', domain: 'amazon.co.jp', purpose: 'prices_world',
        search_url: 'https://www.amazon.co.jp/s?k={q}', notes: 'Precios en yenes.' },
      { name: 'hobbyDB (precios)', domain: 'hobbydb.com', purpose: 'prices_world',
        notes: 'Precios estimados y ventas registradas.' },
      { name: 'Plaza Japan', domain: 'plazajapan.com', purpose: 'prices_world',
        search_url: 'https://www.plazajapan.com/search?q={q}' },
      { name: 'HobbyLink Japan', domain: 'hlj.com', purpose: 'prices_world',
        search_url: 'https://www.hlj.com/search/?q={q}', notes: 'Precios en yenes.' },
      { name: 'Mandarake', domain: 'mandarake.co.jp', purpose: 'prices_world',
        search_url: 'https://order.mandarake.co.jp/order/listPage/list?keyword={q}&lang=en',
        notes: 'Usados y descontinuados de Japón, en yenes.' },
      { name: 'Yahoo! Subastas Japón (terminadas)', domain: 'auctions.yahoo.co.jp', purpose: 'prices_world',
        search_url: 'https://auctions.yahoo.co.jp/closedsearch/closedsearch?p={q}',
        notes: 'Subastas terminadas: precio real de venta, en yenes.' }
    ].freeze

    enum :purpose, { reference: 0, prices_mx: 1, prices_world: 2 }, validate: true

    scope :active, -> { where(active: true) }
    scope :ordered, -> { order(:position, :name) }

    before_validation :normalize

    validates :name, presence: true, length: { maximum: NAME_MAX }
    validates :domain, presence: true, format: { with: DOMAIN_FORMAT, message: 'no es un dominio válido (por ejemplo: ebay.com)' }
    validates :domain, uniqueness: { scope: %i[purpose category], message: 'ya está en esta guía' }
    validates :notes, length: { maximum: NOTES_MAX }
    validate :search_url_is_a_template

    # ¿Ya se guardó alguna guía? Si no, se usan las sugeridas.
    def self.configured?
      exists?
    end

    # Las guías activas en orden (las sugeridas, sin guardar, si no hay ninguna).
    def self.in_use
      configured? ? active.ordered.to_a : DEFAULTS.each_with_index.map { |attrs, i| new(attrs.merge(position: i)) }
    end

    # Guarda las sugeridas para poder editarlas (sólo si todavía no hay ninguna).
    def self.install_defaults!
      return false if configured?

      transaction { DEFAULTS.each_with_index { |attrs, i| create!(attrs.merge(position: i)) } }
      true
    end

    # Dominios de los que se aceptan precios para ese mercado (:mx o :world).
    def self.price_domains(market, sources = in_use)
      purpose = market == :mx ? 'prices_mx' : 'prices_world'
      sources.select { |source| source.purpose == purpose }.map(&:domain).uniq
    end

    # Enlaces para buscar a mano la pieza identificada: los de todas las
    # categorías y los de la suya.
    def self.search_links(query, category: nil)
      return [] if query.blank?

      category = category.to_s.strip.downcase.presence
      in_use.select { |source| source.search_url.present? && [nil, category].include?(source.category) }
            .map { |source| { 'name' => source.name, 'purpose' => source.purpose, 'url' => source.search_url_for(query) } }
    end

    def search_url_for(query)
      search_url.sub(QUERY, ERB::Util.url_encode(query.to_s.strip))
    end

    def purpose_label
      PURPOSE_LABELS[purpose]
    end

    # Cómo se le describe a la IA: «- hobbyDB (hobbydb.com; sólo autos a escala): nota».
    def prompt_line
      scope = [domain, category && "sólo #{category}"].compact.join('; ')
      "- #{name} (#{scope})#{": #{notes}" if notes.present?}"
    end

    private

    # «https://www.eBay.com/itm/1» → «ebay.com»; las categorías van en minúsculas
    # como en CategoryAttributeTemplate.
    def normalize
      self.name = name.to_s.strip
      self.domain = domain.to_s.strip.downcase.sub(%r{\A[a-z]+://}, '').sub(%r{[/?#:].*\z}, '').delete_prefix('www.')
      self.category = category.to_s.strip.downcase.presence
      self.search_url = search_url.to_s.strip.presence
      self.notes = notes.to_s.strip.presence
    end

    def search_url_is_a_template
      return if search_url.blank?

      if search_url.length > URL_MAX
        errors.add(:base, "La búsqueda a mano no puede pasar de #{URL_MAX} caracteres.")
      elsif !search_url.start_with?('https://') || search_url.exclude?(QUERY)
        errors.add(:base, "La búsqueda a mano debe empezar con https:// e incluir #{QUERY} donde va el nombre de la pieza.")
      end
    end
  end
end
