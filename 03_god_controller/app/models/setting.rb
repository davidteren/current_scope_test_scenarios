class Setting < ApplicationRecord
  validates :key, presence: true, uniqueness: true

  def self.[](key)
    find_by(key: key.to_s)&.value
  end

  # Atomic upsert so concurrent first-writes to the same key cannot raise
  # ActiveRecord::RecordNotUnique against the unique index on settings.key.
  def self.[]=(key, value)
    k = key.to_s
    v = value.to_s
    now = Time.current
    upsert({ key: k, value: v, created_at: now, updated_at: now }, unique_by: :index_settings_on_key)
    v
  end
end
