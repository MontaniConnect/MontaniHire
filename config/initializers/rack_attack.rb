ANALYSIS_PATHS = %r{\A/(cv|video)_analyses(/bulk_create\z|\z|/\d+/reanalyse\z)}.freeze

Rack::Attack.cache.store = ActiveSupport::Cache::RedisCacheStore.new(
  url:       ENV.fetch("REDIS_URL", "redis://localhost:6379/0"),
  namespace: "rack_attack"
)

# Super admin safelist — only fires on analysis paths to avoid a DB query on every page load
Rack::Attack.safelist("super_admin") do |req|
  if req.post? && req.path.match?(ANALYSIS_PATHS)
    user_id = req.env["rack.session"]&.[]("user_id")
    user_id && User.where(id: user_id, role: "super_admin").exists?
  end
end

Rack::Attack.safelist("health_check") { |req| req.path == "/up" }

# 10 CV analyses per user per hour
Rack::Attack.throttle("cv_analysis/user", limit: 10, period: 1.hour) do |req|
  if req.post? && req.path.match?(%r{\A/cv_analyses(/bulk_create)?\z})
    req.env["rack.session"]&.[]("user_id")
  end
end

# 10 video analyses per user per hour
Rack::Attack.throttle("video_analysis/user", limit: 10, period: 1.hour) do |req|
  if req.post? && req.path.match?(%r{\A/video_analyses\z})
    req.env["rack.session"]&.[]("user_id")
  end
end

# 3 re-analyses per analysis per hour (keyed on user + analysis ID)
Rack::Attack.throttle("reanalysis/analysis", limit: 3, period: 1.hour) do |req|
  if req.post? && (m = req.path.match(%r{\A/(cv|video)_analyses/(\d+)/reanalyse\z}))
    "#{req.env["rack.session"]&.[]("user_id")}:#{m[1]}:#{m[2]}"
  end
end

# 50 Claude calls per org per day — billing backstop across all analysis types
Rack::Attack.throttle("claude_calls/org", limit: 50, period: 24.hours) do |req|
  if req.post? && req.path.match?(ANALYSIS_PATHS)
    user_id = req.env["rack.session"]&.[]("user_id")
    User.where(id: user_id).pick(:organization_id) if user_id
  end
end

Rack::Attack.throttled_responder = lambda do |req|
  if req.env["HTTP_ACCEPT"]&.include?("application/json")
    [ 429, { "Content-Type" => "application/json" },
      [ { error: "Too many requests. Please try again later." }.to_json ] ]
  else
    [ 429, { "Content-Type" => "text/html" },
      [ "<h1>Too many requests</h1><p>Please try again later.</p>" ] ]
  end
end
