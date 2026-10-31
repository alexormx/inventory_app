# frozen_string_literal: true

class User < ApplicationRecord
  # Include default Devise modules. Others available:
  # :confirmable, :lockable, :timeoutable, :trackable, and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         :confirmable

  before_validation :normalize_blank_email
  # before_validation :generate_placeholder_email, if: :offline_customer?
  before_create :generate_api_token, if: -> { admin? && api_token.blank? }

  has_many :purchase_orders, dependent: :restrict_with_error
  has_many :sale_orders, dependent: :restrict_with_error
  has_many :shopping_carts, dependent: :restrict_with_error
  has_many :shipping_addresses, dependent: :destroy
  has_many :reviews, dependent: :destroy
  has_many :favorites, dependent: :delete_all
  has_many :comments, dependent: :destroy
  has_one :location_assignment_draft, dependent: :destroy

  validates :role, presence: true, inclusion: { in: %w[customer supplier admin] }
  validates :name, length: { maximum: 255 }
  # Optional fields
  validates :phone, format: { with: /\A\d{10}\z/, message: 'Tiene que ser un numero de 10 digitos' }, allow_blank: true
  validates :discount_rate, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }, allow_nil: true

  # modify model to be able to create users without devise, not login.
  validates :password, presence: true, on: :create, unless: :created_by_admin?
  validates :email, uniqueness: true, allow_blank: true, unless: :offline_customer?
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true

  before_destroy :check_dependencies

  # Cuentas que el cliente eliminó (Users::AnonymizeAccount): se conservan por
  # sus pedidos, sin datos personales y sin poder iniciar sesión.
  ANONYMIZED_EMAIL_DOMAIN = 'cuentas-eliminadas.invalid'

  # Cuentas del registro público que no han confirmado su correo. Después de
  # UNVERIFIED_REVIEW_AFTER pasan a revisión en el panel (Usuarios → Cuentas
  # sin verificar). Las creadas por admin o API se confirman al crearse.
  UNVERIFIED_REVIEW_AFTER = 48.hours

  scope :unverified_self_registered, lambda {
    where(role: 'customer', self_registered: true, confirmed_at: nil)
      .where('email IS NULL OR email NOT LIKE ?', "%@#{ANONYMIZED_EMAIL_DOMAIN}")
  }
  scope :unverified_needing_review, lambda {
    unverified_self_registered.where(created_at: ...UNVERIFIED_REVIEW_AFTER.ago)
  }

  def unverified_self_registered?
    self_registered? && confirmed_at.nil? && role == 'customer' && !anonymized?
  end

  def unverified_needs_review?
    unverified_self_registered? && created_at <= UNVERIFIED_REVIEW_AFTER.ago
  end

  def anonymized?
    email.to_s.end_with?("@#{ANONYMIZED_EMAIL_DOMAIN}")
  end

  def active_for_authentication?
    super && !anonymized?
  end

  # Roles
  def admin?
    role == 'admin'
  end

  def created_by_admin?
    !persisted? && role == 'customer'
  end

  def offline_customer?
    role == 'customer' && created_offline?
  end

  # app/models/user.rb
  def created_offline?
    created_offline == true
  end

  def normalize_blank_email
    self.email = nil if email.blank?
  end

  def generate_placeholder_email
    self.email = "offline-#{SecureRandom.hex(6)}@pasatiempos.com" if email.blank?
  end

  # Devise: permitir omitir contraseña para clientes offline creados por API/import
  def password_required?
    return false if offline_customer?

    super
  end

  private

  def check_dependencies
    return unless purchase_orders.exists? || sale_orders.exists?

    errors.add(:base, 'Cannot delete user with associated orders')
    throw(:abort)
  end

  def generate_api_token
    self.api_token = SecureRandom.hex(20)
  end
end
