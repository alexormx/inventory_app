# frozen_string_literal: true

module Admin
  class WhatsappRequestsController < ApplicationController
    before_action :authenticate_user!
    before_action :authorize_admin!
    before_action :set_request, only: %i[show mark_contacted cancel convert_to_sale_order]

    def index
      @status_filter = params[:status].to_s.strip
      @q = params[:q].to_s.strip

      scope = WhatsappRequest.for_admin.includes(:user, whatsapp_request_items: :product).order(created_at: :desc)
      scope = scope.where(status: @status_filter) if @status_filter.present?
      if @q.present?
        pattern = "%#{@q.downcase}%"
        scope = scope.where(
          "LOWER(code) LIKE :p OR LOWER(customer_name) LIKE :p OR LOWER(customer_phone) LIKE :p OR LOWER(customer_email) LIKE :p",
          p: pattern
        )
      end

      @whatsapp_requests = scope.page(params[:page]).per(25)
      @counts = WhatsappRequest.for_admin.group(:status).count
    end

    def show; end

    def mark_contacted
      @request.update!(status: :contacted, contacted_at: Time.current) if @request.sent?
      redirect_to admin_whatsapp_request_path(@request), notice: "Marcado como contactado."
    end

    def cancel
      @request.update!(status: :canceled)
      redirect_to admin_whatsapp_requests_path, notice: "Pedido cancelado."
    end

    def convert_to_sale_order
      if @request.sale_order_id.present?
        redirect_to admin_whatsapp_request_path(@request), alert: "Ya fue convertido a #{@request.sale_order_id}."
        return
      end

      ActiveRecord::Base.transaction do
        target_user = @request.user || resolve_user_from_phone(@request.customer_phone)
        unless target_user
          flash[:alert] = "Necesitamos un usuario asociado. Crea o vincula un User antes de convertir."
          return redirect_to admin_whatsapp_request_path(@request)
        end

        sale_order = SaleOrder.new(
          user: target_user,
          status: 'Pending',
          currency: 'MXN',
          origin: 'whatsapp',
          whatsapp_request_id: @request.id,
          notes: ["Convertido de #{@request.code}", @request.customer_notes].compact.reject(&:blank?).join("\n")
        )

        @request.whatsapp_request_items.each do |item|
          sale_order.sale_order_items.build(
            product: item.product,
            quantity: item.quantity,
            unit_final_price: item.product.selling_price
          )
        end

        sale_order.save!
        @request.update!(status: :converted, sale_order_id: sale_order.id, converted_at: Time.current)

        redirect_to admin_sale_order_path(sale_order), notice: "Lista #{@request.code} convertida a orden #{sale_order.id}."
      end
    rescue ActiveRecord::RecordInvalid => e
      redirect_to admin_whatsapp_request_path(@request), alert: "No se pudo convertir: #{e.record.errors.full_messages.to_sentence}"
    end

    private

    def set_request
      @request = WhatsappRequest.find(params[:id])
    end

    def resolve_user_from_phone(phone)
      return nil if phone.blank?

      digits = phone.to_s.gsub(/\D/, '')
      return nil if digits.blank?

      User.where("regexp_replace(COALESCE(phone, ''), '\\D', '', 'g') = ?", digits).first
    end
  end
end
