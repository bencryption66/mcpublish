class Artifact < ApplicationRecord
  belongs_to :user

  validates :slug, presence: true, uniqueness: true
  validates :storage_key, presence: true
  validates :byte_size, presence: true, numericality: { greater_than: 0 }

  before_validation :assign_slug, on: :create

  def url
    "https://#{Rails.application.config.x.content_host}/p/#{slug}"
  end

  private

  def assign_slug
    self.slug ||= SlugGenerator.generate_unique
  end
end
