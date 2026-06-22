class AddCompensationPackageToCandidates < ActiveRecord::Migration[8.1]
  def change
    add_column :candidates, :compensation_package, :text
  end
end
