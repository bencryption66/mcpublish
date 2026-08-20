require "rails_helper"

RSpec.describe OrganizationInvite, type: :model do
  let(:organization) { Organization.create!(name: "Acme", slug: "acme") }

  it "requires a valid email" do
    invite = OrganizationInvite.new(organization: organization, email: "not-an-email")
    expect(invite).not_to be_valid
  end

  it "is valid with an organization and email" do
    invite = OrganizationInvite.new(organization: organization, email: "invitee@example.com")
    expect(invite).to be_valid
  end

  it "is destroyed when its organization is destroyed" do
    invite = OrganizationInvite.create!(organization: organization, email: "invitee@example.com")
    organization.destroy!

    expect(OrganizationInvite.exists?(invite.id)).to eq(false)
  end
end
