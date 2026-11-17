class ApiRequestLog < ApplicationRecord
  # A removed user must not erase historical diagnostics or block later records.
  belongs_to :user, optional: true

  validates :requested_at, :request_id, :http_method, :path, presence: true
  validates :status, numericality: { only_integer: true, greater_than_or_equal_to: 100, less_than_or_equal_to: 599 }
  validates :duration_ms, numericality: { greater_than_or_equal_to: 0 }
  validates :authentication_method, inclusion: { in: %w[bearer session anonymous] }
  validates :token_fingerprint, format: { with: /\A[0-9a-f]{64}\z/ }, allow_nil: true
end
