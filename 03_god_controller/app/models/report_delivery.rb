class ReportDelivery < ApplicationRecord
  KINDS = %w[legacy_email_report].freeze

  belongs_to :user

  validates :kind, presence: true, inclusion: { in: KINDS }
end
