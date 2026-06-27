namespace :catalog do
  desc 'Genera un PDF de catálogo con datos de MUESTRA (para iterar el diseño)'
  task preview: :environment do
    title = ENV.fetch('TITLE', "CATÁLOGO DEMO #{I18n.l(Date.today, format: '%B %Y').upcase}")
    pdf = CatalogPdf::Generator.new(
      title: title,
      whatsapp_number: Rails.application.config.whatsapp_number,
      items: CatalogPdf::SampleData.items
    ).to_pdf
    write_pdf(pdf, 'catalog_preview')
  end

  desc 'Genera el PDF del catálogo desde productos reales (con ubicación confirmada)'
  task pdf: :environment do
    items = CatalogPdf::ProductSource.items
    abort 'No hay productos con ubicación confirmada.' if items.empty?

    title = ENV.fetch('TITLE', "CATÁLOGO #{I18n.l(Date.today, format: '%B %Y').upcase}")
    pdf = CatalogPdf::Generator.new(
      title: title,
      whatsapp_number: Rails.application.config.whatsapp_number,
      items: items
    ).to_pdf
    write_pdf(pdf, 'catalog')
  end

  desc 'Genera el PDF del catálogo desde PRODUCCIÓN (vía API). Requiere CATALOG_API_URL y CATALOG_API_TOKEN'
  task remote: :environment do
    base_url = ENV.fetch('CATALOG_API_URL') { abort 'Falta CATALOG_API_URL (ej. https://pasatiempos.com.mx)' }
    token    = ENV.fetch('CATALOG_API_TOKEN') { abort 'Falta CATALOG_API_TOKEN (api_token de un admin)' }

    items = CatalogPdf::RemoteSource.items(base_url: base_url, token: token)
    abort 'El catálogo remoto no devolvió productos.' if items.empty?

    title = ENV.fetch('TITLE', "CATÁLOGO #{I18n.l(Date.today, format: '%B %Y').upcase}")
    pdf = CatalogPdf::Generator.new(
      title: title,
      whatsapp_number: Rails.application.config.whatsapp_number,
      items: items
    ).to_pdf
    write_pdf(pdf, 'catalog')
  end

  def write_pdf(pdf, prefix)
    path = Rails.root.join('tmp', "#{prefix}_#{Time.now.strftime('%Y%m%d_%H%M%S')}.pdf")
    File.binwrite(path, pdf)
    puts "PDF generado (#{pdf.bytesize} bytes): #{path}"
  end
end
