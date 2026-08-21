class CreateArtifactShares < ActiveRecord::Migration[8.0]
  def change
    create_table :artifact_shares do |t|
      t.references :artifact, null: false, foreign_key: true
      t.string :email, null: false
      t.references :user, foreign_key: true

      t.timestamps
    end

    add_index :artifact_shares, [ :artifact_id, :email ], unique: true
  end
end
