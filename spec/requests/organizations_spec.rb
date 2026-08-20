require "rails_helper"

RSpec.describe "Organizations", type: :request do
  let(:admin) { User.create!(email: "ivy@example.com", password: "password123", password_confirmation: "password123") }
  let(:member) { User.create!(email: "jack@example.com", password: "password123", password_confirmation: "password123") }

  def sign_in_as(user)
    post "/login", params: { email: user.email, password: "password123" }
  end

  it "requires login" do
    get "/organizations"
    expect(response).to redirect_to("/login")
  end

  it "creates an organization and makes the creator an admin" do
    sign_in_as(admin)

    post "/organizations", params: { organization: { name: "Acme", slug: "acme" } }

    organization = Organization.find_by!(slug: "acme")
    membership = organization.organization_memberships.find_by!(user: admin)
    expect(membership.admin?).to eq(true)
  end

  it "adds an existing user directly as a member when invited" do
    sign_in_as(admin)
    organization = Organization.create!(name: "Acme", slug: "acme")
    OrganizationMembership.create!(user: admin, organization: organization, role: "admin")
    member # eager-create

    post "/organizations/#{organization.id}/invite", params: { email: member.email }

    expect(organization.users).to include(member)
    expect(OrganizationInvite.exists?(organization: organization, email: member.email)).to eq(false)
  end

  it "creates a pending invite for an email with no account yet" do
    sign_in_as(admin)
    organization = Organization.create!(name: "Acme", slug: "acme")
    OrganizationMembership.create!(user: admin, organization: organization, role: "admin")

    post "/organizations/#{organization.id}/invite", params: { email: "notyet@example.com" }

    expect(OrganizationInvite.exists?(organization: organization, email: "notyet@example.com")).to eq(true)
  end

  it "lets an admin remove a member" do
    sign_in_as(admin)
    organization = Organization.create!(name: "Acme", slug: "acme")
    OrganizationMembership.create!(user: admin, organization: organization, role: "admin")
    membership = OrganizationMembership.create!(user: member, organization: organization, role: "member")

    delete "/organizations/#{organization.id}/members/#{membership.id}"

    expect(OrganizationMembership.exists?(membership.id)).to eq(false)
  end

  it "does not let a non-admin member remove anyone" do
    sign_in_as(member)
    organization = Organization.create!(name: "Acme", slug: "acme")
    OrganizationMembership.create!(user: admin, organization: organization, role: "admin")
    membership = OrganizationMembership.create!(user: member, organization: organization, role: "member")

    delete "/organizations/#{organization.id}/members/#{membership.id}"

    expect(response).to have_http_status(:not_found)
    expect(OrganizationMembership.exists?(membership.id)).to eq(true)
  end

  it "does not let the last admin remove themselves" do
    sign_in_as(admin)
    organization = Organization.create!(name: "Acme", slug: "acme")
    admin_membership = OrganizationMembership.create!(user: admin, organization: organization, role: "admin")

    delete "/organizations/#{organization.id}/members/#{admin_membership.id}"

    expect(OrganizationMembership.exists?(admin_membership.id)).to eq(true)
  end

  it "redirects to the organizations list when an admin removes themselves from an org with other admins left" do
    sign_in_as(admin)
    organization = Organization.create!(name: "Acme", slug: "acme")
    admin_membership = OrganizationMembership.create!(user: admin, organization: organization, role: "admin")
    OrganizationMembership.create!(user: member, organization: organization, role: "admin")

    delete "/organizations/#{organization.id}/members/#{admin_membership.id}"

    expect(response).to redirect_to("/organizations")
    expect(OrganizationMembership.exists?(admin_membership.id)).to eq(false)
  end
end
