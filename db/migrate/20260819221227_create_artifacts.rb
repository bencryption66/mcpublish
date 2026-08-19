class CreateArtifacts < ActiveRecord::Migration[8.0]
  def change
    create_table :artifacts do |t|
      t.string :slug, null: false
      t.references :api_key, null: false, foreign_key: true
      t.string :storage_key, null: false
      t.integer :byte_size, null: false

      t.timestamps
    end

    add_index :artifacts, :slug, unique: true
  end
end
