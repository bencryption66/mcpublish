require "rails_helper"

RSpec.describe User, type: :model do
  it "creates a user with a valid email and password" do
    user = User.new(email: "Alice@Example.com", password: "password123", password_confirmation: "password123")
    expect(user).to be_valid
  end

  it "normalizes email to lowercase on save" do
    user = User.create!(email: "Alice@Example.com", password: "password123", password_confirmation: "password123")
    expect(user.email).to eq("alice@example.com")
  end

  it "requires a unique email, case-insensitively" do
    User.create!(email: "alice@example.com", password: "password123", password_confirmation: "password123")
    dupe = User.new(email: "ALICE@example.com", password: "password123", password_confirmation: "password123")

    expect(dupe).not_to be_valid
  end

  it "rejects a malformed email" do
    user = User.new(email: "not-an-email", password: "password123", password_confirmation: "password123")
    expect(user).not_to be_valid
  end

  it "requires a password of at least 8 characters" do
    user = User.new(email: "bob@example.com", password: "short", password_confirmation: "short")
    expect(user).not_to be_valid
  end

  it "authenticates with the correct password" do
    user = User.create!(email: "carol@example.com", password: "password123", password_confirmation: "password123")
    expect(user.authenticate("password123")).to eq(user)
    expect(user.authenticate("wrong")).to eq(false)
  end
end
