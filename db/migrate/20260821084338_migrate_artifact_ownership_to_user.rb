class MigrateArtifactOwnershipToUser < ActiveRecord::Migration[8.0]
  def up
    add_reference :artifacts, :user, foreign_key: true

    execute <<~SQL
      UPDATE artifacts
      SET user_id = api_keys.user_id
      FROM api_keys
      WHERE api_keys.id = artifacts.api_key_id
    SQL

    orphaned = select_value("SELECT count(*) FROM artifacts WHERE user_id IS NULL").to_i
    if orphaned > 0
      raise ActiveRecord::IrreversibleMigration,
        "#{orphaned} artifact(s) have no resolvable owning user (their api_key has no user) - " \
        "resolve this manually before this migration can safely drop api_key_id"
    end

    change_column_null :artifacts, :user_id, false
    remove_reference :artifacts, :api_key, foreign_key: true
  end

  def down
    add_reference :artifacts, :api_key, foreign_key: true
    change_column_null :artifacts, :user_id, true
    remove_reference :artifacts, :user, foreign_key: true
  end
end
