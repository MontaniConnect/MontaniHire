class AddJobSourceToCandidates < ActiveRecord::Migration[8.0]
  def change
    add_column :candidates, :job_source,       :string
    add_column :candidates, :job_source_other, :string
  end
end
