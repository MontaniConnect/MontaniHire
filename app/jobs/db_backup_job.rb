class DbBackupJob < ApplicationJob
  queue_as :default

  def perform
    require "aws-sdk-s3"

    timestamp = Time.current.utc.strftime("%Y%m%d_%H%M%S")
    dump_path = Rails.root.join("tmp", "backup_#{timestamp}.dump").to_s
    gz_path   = "#{dump_path}.gz"
    s3_key    = "backups/backup_#{timestamp}.dump.gz"
    bucket    = ENV.fetch("S3_BUCKET")

    begin
      db_url = ENV.fetch("DATABASE_URL")

      system("pg_dump", "--format=custom", "--no-acl", "--no-owner", "-f", dump_path, db_url) ||
        raise("pg_dump failed (exit #{$?.exitstatus})")
      raise "pg_dump produced empty dump" if File.size(dump_path).zero?

      system("gzip", dump_path) || raise("gzip failed (exit #{$?.exitstatus})")
      # gzip replaces dump_path with dump_path.gz in place

      s3 = Aws::S3::Client.new(
        region:            ENV.fetch("AWS_REGION"),
        access_key_id:     ENV.fetch("AWS_ACCESS_KEY_ID"),
        secret_access_key: ENV.fetch("AWS_SECRET_ACCESS_KEY")
      )

      File.open(gz_path, "rb") { |f| s3.put_object(bucket: bucket, key: s3_key, body: f) }
      Rails.logger.info "[DbBackupJob] Uploaded #{s3_key} (#{File.size(gz_path)} bytes)"

      cutoff = 30.days.ago
      s3.list_objects_v2(bucket: bucket, prefix: "backups/").contents.each do |obj|
        next unless obj.last_modified < cutoff
        s3.delete_object(bucket: bucket, key: obj.key)
        Rails.logger.info "[DbBackupJob] Pruned #{obj.key}"
      end
    ensure
      File.delete(dump_path) if File.exist?(dump_path)
      File.delete(gz_path)   if File.exist?(gz_path)
    end
  end
end
