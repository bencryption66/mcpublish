class CreateApiKeys < ActiveRecord::Migration[8.0]
  def change
    create_table :api_keys do |t|
      t.string :token_digest, null: false
      t.string :label, null: false
      t.datetime :revoked_at

      t.timestamps
    end

    add_index :api_keys, :token_digest, unique: true
  end
end
