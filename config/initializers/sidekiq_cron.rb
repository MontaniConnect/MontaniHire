Sidekiq.configure_server do |config|
  config.on(:startup) do
    schedule_file = Rails.root.join("config/sidekiq.yml")
    if File.exist?(schedule_file)
      schedule = YAML.load_file(schedule_file, symbolize_names: true)[:schedule]
      Sidekiq::Cron::Job.load_from_hash(schedule.transform_keys(&:to_s)) if schedule
    end
  end
end
