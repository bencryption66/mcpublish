class CreateOrganizationInvites < ActiveRecord::Migration[8.0]
  def change
    create_table :organization_invites do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :email, null: false

      t.timestamps
    end

    add_index :organization_invites, [ :organization_id, :email ], unique: true
  end
end
