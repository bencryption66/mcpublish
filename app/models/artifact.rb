class Artifact < ApplicationRecord
  belongs_to :user
  belongs_to :organization, optional: true

  VISIBILITIES = %w[private organisation shared public].freeze

  validates :slug, presence: true, uniqueness: true
  validates :storage_key, presence: true
  validates :byte_size, presence: true, numericality: { greater_than: 0 }
  validates :visibility, inclusion: { in: VISIBILITIES }
  validates :organization, presence: true, if: -> { visibility == "organisation" }
  validate :no_organization_unless_organisation_visibility

  before_validation :assign_slug, on: :create

  def url
    "https://#{Rails.application.config.x.content_host}/p/#{slug}"
  end

  private

  def assign_slug
    self.slug ||= SlugGenerator.generate_unique
  end

  def no_organization_unless_organisation_visibility
    return unless organization.present? && visibility != "organisation"

    errors.add(:organization, "must be blank unless visibility is organisation")
  end
end
