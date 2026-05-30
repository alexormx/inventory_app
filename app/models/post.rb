# frozen_string_literal: true

class Post < ApplicationRecord
  extend FriendlyId
  friendly_id :title, use: :slugged

  belongs_to :user
  has_many :comments, dependent: :destroy
  has_rich_text :body
  has_one_attached :cover_image

  # Virtual attribute: cuando el admin pega HTML directo (modo "código"),
  # se asigna al body via Action Text al guardar. Tiene precedencia sobre
  # lo que produce el editor Trix. Action Text se encarga de sanitizar
  # tags peligrosos (scripts, iframes, style attrs, etc.).
  attr_accessor :body_html_raw

  before_save :apply_body_html_raw

  enum :status, { draft: 0, published: 1, archived: 2 }, default: :draft
  enum :editor_mode, { wysiwyg: 0, html: 1 }, default: :wysiwyg, prefix: :editor

  validates :title, presence: true, length: { maximum: 200 }
  validates :excerpt, length: { maximum: 500 }
  validates :meta_description, length: { maximum: 320 }

  before_save :stamp_published_at

  # Returns the post's body HTML with Action Text's outer
  # <div class="trix-content"> wrapper stripped — useful for the
  # admin form's HTML textarea so the author edits inner content
  # only and doesn't accumulate nested wrappers on each save.
  def body_inner_html
    raw = body&.body&.to_s.to_s
    raw.sub(%r{\A<div class="trix-content">\s*(.*?)\s*</div>\s*\z}m, '\1')
  end

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

  # Only apply the raw HTML when the author explicitly chose HTML mode.
  # In WYSIWYG mode the textarea might still carry pre-fill content from
  # a previous HTML session — ignoring it prevents an accidental
  # overwrite of the Trix output.
  def apply_body_html_raw
    return unless editor_html?
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
