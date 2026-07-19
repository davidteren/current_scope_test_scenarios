class ReportDelivery < ApplicationRecord
  belongs_to :user

  validates :kind, presence: true
end
