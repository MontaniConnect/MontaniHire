namespace :db do
  desc "pg_dump → gzip → S3 under backups/; retain last 30 days"
  task backup: :environment do
    DbBackupJob.perform_now
  end
end
