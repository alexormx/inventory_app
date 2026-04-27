# frozen_string_literal: true

module WhatsappListsHelper
  def whatsapp_list_item_count
    request = current_whatsapp_request_safe
    request ? request.total_items : 0
  end

  def current_whatsapp_request_safe
    if respond_to?(:user_signed_in?) && user_signed_in?
      WhatsappRequest.where(user_id: current_user.id, status: WhatsappRequest.statuses[:draft]).order(created_at: :desc).first ||
        whatsapp_request_by_token
    else
      whatsapp_request_by_token
    end
  rescue StandardError
    nil
  end

  def whatsapp_request_by_token
    token = cookies.signed[:wa_list_token] if respond_to?(:cookies)
    return nil if token.blank?

    WhatsappRequest.where(session_token: token, status: WhatsappRequest.statuses[:draft]).first
  end
end
