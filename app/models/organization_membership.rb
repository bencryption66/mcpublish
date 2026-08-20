class OrganizationMembership < ApplicationRecord
  belongs_to :user
  belongs_to :organization

  ROLES = %w[admin member].freeze

  validates :role, inclusion: { in: ROLES }
  validates :user_id, uniqueness: { scope: :organization_id }

  def admin?
    role == "admin"
  end
end
