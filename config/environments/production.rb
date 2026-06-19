require "active_support/core_ext/integer/time"


Rails.application.configure do
  config.secret_key_base = ENV.fetch("SECRET_KEY_BASE") { SecureRandom.hex(64) }

  # Settings specified here will take precedence over those in config/application.rb.

  config.active_storage.service = :amazon

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot for better performance and memory savings (ignored by Rake tasks).
  config.eager_load = true

  # Full error reports are disabled.
  config.consider_all_requests_local = false

  # Cache assets for far-future expiry since they are all digest stamped.
  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.asset_host = "http://assets.example.com"

  # Railway terminates SSL at the load balancer — trust that it happened.
  config.assume_ssl = true

  # Log to STDOUT with the current request id as a default log tag.
  config.log_tags = [ :request_id ]
  config.logger   = ActiveSupport::TaggedLogging.logger(STDOUT)

  # Change to "debug" to log everything (including potentially personally-identifiable information!).
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Prevent health checks from clogging up the logs.
  config.silence_healthcheck_path = "/up"

  # Don't log any deprecations.
  config.active_support.report_deprecations = false
  config.active_job.queue_adapter = :async
  # # Replace the default in-process memory cache store with a durable alternative.
  # config.cache_store = :solid_cache_store

  # # Replace the default in-process and non-durable queuing backend for Active Job.
  # config.active_job.queue_adapter = :solid_queue
  # # config.solid_queue.connects_to = { database: { writing: :queue } }

  # Set host for mailer templates and for _url helpers called outside request context (e.g. Shortlist#share_url).
  config.action_mailer.default_url_options = {
    host:     ENV.fetch("RAILWAY_PUBLIC_DOMAIN", "localhost"),
    protocol: "https"
  }
  Rails.application.routes.default_url_options = {
    host:     ENV.fetch("RAILWAY_PUBLIC_DOMAIN", "localhost"),
    protocol: "https"
  }

  # Specify outgoing SMTP server. Remember to add smtp/* credentials via bin/rails credentials:edit.
  # config.action_mailer.smtp_settings = {
  #   user_name: Rails.application.credentials.dig(:smtp, :user_name),
  #   password: Rails.application.credentials.dig(:smtp, :password),
  #   address: "smtp.example.com",
  #   port: 587,
  #   authentication: :plain
  # }

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Only use :id for inspections in production.
  config.active_record.attributes_for_inspect = [ :id ]

  # Allow requests from the Railway-assigned domain (and any custom domain you add).
  config.hosts << ENV["RAILWAY_PUBLIC_DOMAIN"] if ENV["RAILWAY_PUBLIC_DOMAIN"].present?

  # Exclude the healthcheck path from host authorization — Railway's internal
  # healthcheck system sends requests from a different host than the public domain.
  config.host_authorization = { exclude: ->(request) { request.path == "/up" } }

  config.x.invites_enabled = true
end
