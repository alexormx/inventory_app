# frozen_string_literal: true

class Comment < ApplicationRecord
  belongs_to :post
  belongs_to :user

  enum :status, { pending: 0, approved: 1, rejected: 2 }, default: :pending

  validates :body, presence: true, length: { minimum: 3, maximum: 2000 }

  before_save :stamp_approved_at

  scope :visible, -> { approved.order(created_at: :asc) }

  def author_name
    user&.name.presence || user&.email&.split('@')&.first || 'Usuario'
  end

  private

  def stamp_approved_at
    if status_changed? && approved?
      self.approved_at ||= Time.current
    elsif status_changed? && !approved?
      self.approved_at = nil
    end
  end
end
