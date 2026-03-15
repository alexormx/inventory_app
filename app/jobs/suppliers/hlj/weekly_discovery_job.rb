# frozen_string_literal: true

module Suppliers
  module Hlj
    class WeeklyDiscoveryJob < ApplicationJob
      queue_as :default

      retry_on StandardError, wait: :polynomially_longer, attempts: 3

      def perform
        Suppliers::Hlj::DiscoveryService.new.call
      end
    end
  end
end