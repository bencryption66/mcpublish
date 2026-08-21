class Organization < ApplicationRecord
  has_many :organization_memberships, dependent: :destroy
  has_many :organization_invites, dependent: :destroy
  has_many :users, through: :organization_memberships
  has_many :artifacts, dependent: :restrict_with_exception

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true,
    format: { with: /\A[a-z0-9-]+\z/, message: "may only contain lowercase letters, numbers, and hyphens" }
end
