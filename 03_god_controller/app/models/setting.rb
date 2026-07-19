class Setting < ApplicationRecord
  validates :key, presence: true, uniqueness: true

  def self.[](key)
    find_by(key: key.to_s)&.value
  end

  def self.[]=(key, value)
    rec = find_or_initialize_by(key: key.to_s)
    rec.value = value.to_s
    rec.save!
    rec.value
  end
end
