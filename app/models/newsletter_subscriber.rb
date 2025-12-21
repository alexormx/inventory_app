# frozen_string_literal: true

class NewsletterSubscriber < ApplicationRecord
  validates :email, presence: true,
                    uniqueness: { case_sensitive: false },
                    format: { with: URI::MailTo::EMAIL_REGEXP }

  before_save :downcase_email

  scope :active, -> { where(unsubscribed_at: nil) }

  def subscribe!
    update!(subscribed_at: Time.current, unsubscribed_at: nil)
  end

  def unsubscribe!
    update!(unsubscribed_at: Time.current)
  end

  private

  def downcase_email
    self.email = email.downcase.strip
  end
end
