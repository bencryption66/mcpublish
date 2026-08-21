class AddVisibilityToArtifacts < ActiveRecord::Migration[8.0]
  def change
    add_column :artifacts, :visibility, :string, null: false, default: "private"
    add_reference :artifacts, :organization, foreign_key: true
  end
end
