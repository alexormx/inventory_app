# frozen_string_literal: true

class WhatsappRequestMailer < ApplicationMailer
  def new_request_admin(whatsapp_request_id)
    @request = WhatsappRequest.find(whatsapp_request_id)
    admin_email = SiteSetting.get('whatsapp_admin_email', '').to_s.strip
    return if admin_email.blank?

    mail(
      to: admin_email,
      subject: "[Pasatiempos] Nuevo pedido WhatsApp #{@request.code}"
    )
  end
end
