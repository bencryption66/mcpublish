class OrganizationInvite < ApplicationRecord
  belongs_to :organization

  before_validation :normalize_email

  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }

  private

  def normalize_email
    self.email = email.to_s.strip.downcase
  end
end
