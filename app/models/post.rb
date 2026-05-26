# frozen_string_literal: true

class Post < ApplicationRecord
  extend FriendlyId
  friendly_id :title, use: :slugged

  belongs_to :user
  has_rich_text :body
  has_one_attached :cover_image

  enum :status, { draft: 0, published: 1, archived: 2 }, default: :draft

  validates :title, presence: true, length: { maximum: 200 }
  validates :excerpt, length: { maximum: 500 }
  validates :meta_description, length: { maximum: 320 }

  before_save :stamp_published_at

  scope :visible, -> { published.where('published_at <= ?', Time.current).order(published_at: :desc) }

  def should_generate_new_friendly_id?
    title_changed? || slug.blank?
  end

  def author_name
    user&.name.presence || user&.email&.split('@')&.first || 'Pasatiempos a Escala'
  end

  private

  def stamp_published_at
    return unless status_changed?

    if published? && published_at.blank?
      self.published_at = Time.current
    elsif !published?
      self.published_at = nil
    end
  end
end
