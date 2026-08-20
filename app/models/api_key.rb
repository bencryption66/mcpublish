class ApiKey < ApplicationRecord
  belongs_to :user, optional: true
  has_many :artifacts, dependent: :destroy

  TOKEN_PREFIX = "mcpub_".freeze

  validates :label, presence: true
  validates :token_digest, presence: true, uniqueness: true

  def self.issue!(label:, user: nil)
    raw_token = TOKEN_PREFIX + SecureRandom.hex(32)
    api_key = create!(label: label, user: user, token_digest: digest(raw_token))
    [ api_key, raw_token ]
  end

  def self.authenticate(raw_token)
    return nil if raw_token.blank?

    api_key = find_by(token_digest: digest(raw_token))
    return nil if api_key.nil?
    return nil if api_key.revoked?

    api_key
  end

  def revoked?
    revoked_at.present?
  end

  def self.digest(raw_token)
    Digest::SHA256.hexdigest(raw_token)
  end
  private_class_method :digest
end
