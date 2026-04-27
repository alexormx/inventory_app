# frozen_string_literal: true

class WhatsappRequest < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :sale_order, optional: true
  has_many :whatsapp_request_items, dependent: :destroy
  has_many :products, through: :whatsapp_request_items

  enum :status, { draft: 0, sent: 1, contacted: 2, converted: 3, canceled: 4 }, default: :draft

  validates :customer_name, presence: true, if: -> { sent? || contacted? || converted? }
  validates :code, uniqueness: { allow_nil: true }

  scope :recent, -> { order(created_at: :desc) }
  scope :active, -> { where(status: %i[sent contacted]) }
  scope :for_admin, -> { where.not(status: :draft) }

  after_update :notify_admin_if_just_sent, if: :saved_change_to_status?

  def total_items
    whatsapp_request_items.sum(:quantity)
  end

  def recompute_total!
    self.total_estimate = whatsapp_request_items.sum('quantity * COALESCE(unit_price_snapshot, 0)')
    save!
  end

  def mark_sent!(attrs = {})
    assign_attributes(attrs)
    self.status = :sent
    self.sent_at = Time.current
    self.code ||= generate_code
    self.total_estimate = whatsapp_request_items.sum('quantity * COALESCE(unit_price_snapshot, 0)')
    save!
  end

  def whatsapp_message_body(tracking_url: nil)
    lines = []
    lines << "Hola, quiero hacer un pedido por catálogo."
    lines << "Código: *#{code}*"
    lines << ""
    lines << "Items:"
    whatsapp_request_items.includes(:product).each do |item|
      product = item.product
      sku = product.supplier_product_code.presence || product.product_sku
      price = item.unit_price_snapshot.to_f
      lines << "• #{sku} — #{product.product_name} · qty #{item.quantity} · ~$#{format('%.0f', price)} c/u"
    end
    lines << ""
    lines << "Total estimado: ~$#{format('%.0f', total_estimate.to_f)}"
    lines << ""
    lines << "Notas: #{customer_notes}" if customer_notes.present?
    lines << "Estatus en línea: #{tracking_url}" if tracking_url.present?
    lines.join("\n")
  end

  def whatsapp_url(phone_override: nil, tracking_url: nil)
    phone = phone_override || SiteSetting.get('whatsapp_orders_phone', '')
    return nil if phone.blank?

    digits = phone.to_s.gsub(/\D/, '')
    "https://wa.me/#{digits}?text=#{CGI.escape(whatsapp_message_body(tracking_url: tracking_url))}"
  end

  private

  def notify_admin_if_just_sent
    return unless sent? && saved_change_to_status?[0] == 'draft'
    return if SiteSetting.get('whatsapp_admin_email', '').to_s.strip.blank?

    WhatsappRequestMailer.new_request_admin(id).deliver_later
  rescue StandardError => e
    Rails.logger.warn("[WhatsappRequest##{id}] notify failure: #{e.class}: #{e.message}")
  end

  def generate_code
    year = Date.current.year
    last = self.class.where("code LIKE ?", "WA-#{year}-%").order(code: :desc).first
    next_seq = if last && (m = last.code.match(/WA-#{year}-(\d+)/))
                 m[1].to_i + 1
               else
                 1
               end
    "WA-#{year}-#{next_seq.to_s.rjust(4, '0')}"
  end
end
