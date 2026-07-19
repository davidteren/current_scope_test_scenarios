class User < ApplicationRecord
  has_many :reports, foreign_key: :requested_by_id, dependent: :destroy
end
