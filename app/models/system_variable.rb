class SystemVariable < ApplicationRecord
  validates :name, presence: true, uniqueness: true

  def self.get(name, default=nil)
    find_by(name: name)&.value.presence || default
  end

  def self.set(name, value, description: nil)
    rec = find_or_initialize_by(name: name)
    rec.value = value
    rec.description = description if description
    rec.save!
    rec
  end
end
