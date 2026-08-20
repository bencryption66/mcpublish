require "rails_helper"

RSpec.describe OrganizationMembership, type: :model do
  let(:user) { User.create!(email: "hank@example.com", password: "password123", password_confirmation: "password123") }
  let(:organization) { Organization.create!(name: "Acme", slug: "acme") }

  it "accepts admin and member roles" do
    membership = OrganizationMembership.new(user: user, organization: organization, role: "admin")
    expect(membership).to be_valid
  end

  it "rejects an invalid role" do
    membership = OrganizationMembership.new(user: user, organization: organization, role: "owner")
    expect(membership).not_to be_valid
  end

  it "prevents the same user joining the same org twice" do
    OrganizationMembership.create!(user: user, organization: organization, role: "member")
    dupe = OrganizationMembership.new(user: user, organization: organization, role: "member")

    expect(dupe).not_to be_valid
  end

  it "reports admin? correctly" do
    admin = OrganizationMembership.new(role: "admin")
    member = OrganizationMembership.new(role: "member")

    expect(admin.admin?).to eq(true)
    expect(member.admin?).to eq(false)
  end

  it "is reachable via user#organizations and organization#users" do
    OrganizationMembership.create!(user: user, organization: organization, role: "admin")

    expect(user.organizations).to include(organization)
    expect(organization.users).to include(user)
  end
end
