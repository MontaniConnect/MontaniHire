class CreateSalaryBenchmarks < ActiveRecord::Migration[8.1]
  def change
    create_table :salary_benchmarks do |t|
      t.timestamps
    end
  end
end
