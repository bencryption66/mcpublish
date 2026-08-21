class ArtifactShare < ApplicationRecord
  belongs_to :artifact
  belongs_to :user, optional: true

  before_validation :normalize_email

  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :email, uniqueness: { scope: :artifact_id, case_sensitive: false }

  private

  def normalize_email
    self.email = email.to_s.strip.downcase
  end
end
