class MigrateArtifactOwnershipToUser < ActiveRecord::Migration[8.0]
  def change
    add_reference :artifacts, :user, foreign_key: true
    remove_reference :artifacts, :api_key, foreign_key: true
  end
end
