class CreateSalaryInsights < ActiveRecord::Migration[8.1]
  def change
    create_table :salary_insights do |t|
      t.timestamps
    end
  end
end
