class AddNoShowAndHiredAtToCandidates < ActiveRecord::Migration[8.0]
  def change
    add_column :candidates, :no_show, :boolean, default: false, null: false
    add_column :candidates, :hired_at, :datetime
  end
end
