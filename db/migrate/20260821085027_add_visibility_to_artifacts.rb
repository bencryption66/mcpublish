class AddVisibilityToArtifacts < ActiveRecord::Migration[8.0]
  def up
    add_column :artifacts, :visibility, :string, null: false, default: "private"
    add_reference :artifacts, :organization, foreign_key: true

    # Every artifact that already existed before this migration predates the
    # visibility concept and was served unconditionally by ContentController
    # (no gating existed yet) - default them to public so already-shared
    # links keep working. New artifacts (created after this deploy) get
    # "private" from the column default / the MCP tools' explicit default.
    execute "UPDATE artifacts SET visibility = 'public'"
  end

  def down
    remove_reference :artifacts, :organization, foreign_key: true
    remove_column :artifacts, :visibility
  end
end
