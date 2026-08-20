require "rails_helper"

RSpec.describe Organization, type: :model do
  it "requires a name" do
    org = Organization.new(slug: "acme")
    expect(org).not_to be_valid
  end

  it "requires a unique slug" do
    Organization.create!(name: "Acme", slug: "acme")
    dupe = Organization.new(name: "Acme Two", slug: "acme")

    expect(dupe).not_to be_valid
  end

  it "rejects a slug with invalid characters" do
    org = Organization.new(name: "Acme", slug: "Not Valid!")
    expect(org).not_to be_valid
  end

  it "accepts a lowercase, hyphenated slug" do
    org = Organization.new(name: "Acme", slug: "acme-co")
    expect(org).to be_valid
  end
end
