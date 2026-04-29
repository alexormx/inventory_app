# frozen_string_literal: true

module WhatsappListsHelper
  def whatsapp_list_item_count
    request = current_whatsapp_request_safe
    request ? request.total_items : 0
  end

  # La lista de WhatsApp es solo para invitados. Si el usuario está logeado debe usar el carrito.
  def whatsapp_list_available?
    !(respond_to?(:user_signed_in?) && user_signed_in?)
  end

  def current_whatsapp_request_safe
    return nil unless whatsapp_list_available?

    whatsapp_request_by_token
  rescue StandardError
    nil
  end

  def whatsapp_request_by_token
    token = cookies.signed[:wa_list_token] if respond_to?(:cookies)
    return nil if token.blank?

    WhatsappRequest.where(session_token: token, status: WhatsappRequest.statuses[:draft]).first
  end
end
