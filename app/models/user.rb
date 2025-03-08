class User < ApplicationRecord
  # Include default Devise modules. Others available:
  # :confirmable, :lockable, :timeoutable, :trackable, and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  has_many :purchase_orders, foreign_key: :user_id, dependent: :restrict_with_error
  has_many :sale_orders, foreign_key: :user_id, dependent: :restrict_with_error

  validates :role, presence: true, inclusion: { in: %w[customer supplier admin] }
  validates :name, length: { maximum: 255 }
  validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  # Optional fields
  validates :phone, format: { with: /\A\d{10}\z/, message: "Tiene que ser un numer de 10 digitos" }, allow_blank: true

  validates :discount_rate, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }, allow_nil: true

  before_destroy :check_dependencies

  private

  def check_dependencies
    if purchase_orders.exists? || sale_orders.exists?
      errors.add(:base, "Cannot delete user with associated orders")
      throw(:abort)
    end
  end
end