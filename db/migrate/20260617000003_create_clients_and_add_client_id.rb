class CreateClientsAndAddClientId < ActiveRecord::Migration[8.1]
  def up
    create_table :clients do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :name,          null: false
      t.string :contact_email
      t.string :logo_url
      t.timestamps
    end
    add_index :clients, [ :organization_id, :name ]

    add_reference :job_roles,  :client, null: true, foreign_key: true
    add_reference :shortlists, :client, null: true, foreign_key: true

    backfill_clients
  end

  def down
    remove_reference :shortlists, :client, foreign_key: true
    remove_reference :job_roles,  :client, foreign_key: true
    drop_table :clients
  end

  private

  def backfill_clients
    say_with_time "Backfilling Client records from shortlist.client_name" do
      groups = connection.execute(<<~SQL).to_a
        SELECT
          organization_id,
          MIN(TRIM(client_name))                                                               AS name,
          MIN(client_logo_url) FILTER (WHERE TRIM(COALESCE(client_logo_url, '')) != '')        AS logo_url,
          ARRAY_AGG(id ORDER BY created_at)                                                   AS ids
        FROM shortlists
        WHERE TRIM(COALESCE(client_name, '')) != ''
        GROUP BY organization_id, LOWER(TRIM(client_name))
        ORDER BY organization_id, 1
      SQL

      groups.each do |row|
        result = connection.execute(<<~SQL)
          INSERT INTO clients (organization_id, name, logo_url, created_at, updated_at)
          VALUES (
            #{row['organization_id'].to_i},
            #{connection.quote(row['name'])},
            #{row['logo_url'] ? connection.quote(row['logo_url']) : 'NULL'},
            NOW(), NOW()
          )
          RETURNING id
        SQL
        client_id = result.first['id'].to_i

        ids = row['ids'].delete('{}').split(',').map(&:to_i).reject(&:zero?)
        unless ids.empty?
          connection.execute(
            "UPDATE shortlists SET client_id = #{client_id} WHERE id IN (#{ids.join(',')})"
          )
        end

        say "  ✓ #{row['name'].inspect} (org #{row['organization_id']}) — #{ids.size} shortlist(s) assigned", true
      end

      groups.size
    end
  end
end
