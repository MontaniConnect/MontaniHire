class AddCandidateToShortlistItems < ActiveRecord::Migration[8.1]
  def change
    add_reference :shortlist_items, :candidate, null: true, foreign_key: true

    # Allow shareable to be omitted when a Candidate is the primary reference
    change_column_null :shortlist_items, :shareable_type, true
    change_column_null :shortlist_items, :shareable_id,   true
  end
end
