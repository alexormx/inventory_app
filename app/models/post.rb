# frozen_string_literal: true

class Post < ApplicationRecord
  extend FriendlyId
  friendly_id :title, use: :slugged

  belongs_to :user
  has_rich_text :body
  has_one_attached :cover_image

  # Virtual attribute: cuando el admin pega HTML directo (modo "código"),
  # se asigna al body via Action Text al guardar. Tiene precedencia sobre
  # lo que produce el editor Trix. Action Text se encarga de sanitizar
  # tags peligrosos (scripts, iframes, style attrs, etc.).
  attr_accessor :body_html_raw

  before_save :apply_body_html_raw

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

  # Approximate reading time in minutes from the body's word count.
  # Uses 220 wpm (Spanish reading average) and rounds up so a 1-word
  # post still reports "1 min".
  def reading_time_minutes
    text = body.to_plain_text.to_s
    words = text.split(/\s+/).reject(&:empty?).size
    [(words / 220.0).ceil, 1].max
  end

  private

  def apply_body_html_raw
    return if body_html_raw.blank?

    self.body = body_html_raw
  end

  def stamp_published_at
    return unless status_changed?

    if published? && published_at.blank?
      self.published_at = Time.current
    elsif !published?
      self.published_at = nil
    end
  end
end
