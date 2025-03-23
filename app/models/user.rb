class User < ApplicationRecord
  # Include default Devise modules. Others available:
  # :confirmable, :lockable, :timeoutable, :trackable, and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  before_validation :normalize_blank_email
  #before_validation :generate_placeholder_email, if: :offline_customer?

  has_many :purchase_orders, foreign_key: :user_id, dependent: :restrict_with_error
  has_many :sale_orders, foreign_key: :user_id, dependent: :restrict_with_error

  validates :role, presence: true, inclusion: { in: %w[customer supplier admin] }
  validates :name, length: { maximum: 255 }
  # Optional fields
  validates :phone, format: { with: /\A\d{10}\z/, message: "Tiene que ser un numero de 10 digitos" }, allow_blank: true
  validates :discount_rate, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }, allow_nil: true

  #modify model to be able to create users without devise, not login.
  validates :password, presence: true, on: :create, unless: :created_by_admin?
  validates :email, uniqueness: true, allow_blank: true, unless: :offline_customer?
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true

  before_destroy :check_dependencies

  # Roles
  def admin?
    role == "admin"
  end

  def created_by_admin?
    !persisted? && role == "customer"
  end

  def offline_customer?
    role == "customer" && created_offline?
  end

  # app/models/user.rb
  def created_offline?
    self.created_offline == true
  end

  def normalize_blank_email
    self.email = nil if email.blank?
  end

  def generate_placeholder_email
    self.email = "offline-#{SecureRandom.hex(6)}@pasatiempos.com" if email.blank?
  end

  private

  def check_dependencies
    if purchase_orders.exists? || sale_orders.exists?
      errors.add(:base, "Cannot delete user with associated orders")
      throw(:abort)
    end
  end
end
