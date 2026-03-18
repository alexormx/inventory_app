# frozen_string_literal: true

module Suppliers
  class RefreshSourceJob < ApplicationJob
    queue_as :default

    retry_on Net::ReadTimeout, Net::OpenTimeout, Faraday::TimeoutError,
             wait: 10.seconds, attempts: 2

    SERVICES = {
      "hlj" => "Suppliers::Hlj::RefreshItemService",
      "takaratomy_mall" => "Suppliers::TakaraTomyMall::BackfillItemService",
      "tomica_fandom" => "Suppliers::TomicaFandom::BackfillItemService"
    }.freeze

    def perform(catalog_item_id, source_key)
      catalog_item = SupplierCatalogItem.find(catalog_item_id)
      service_class = SERVICES[source_key]
      raise ArgumentError, "Unknown source: #{source_key}" unless service_class

      service_class.constantize.new(catalog_item).call
    end
  end
end
