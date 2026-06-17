# Episode v9 quality audit — rails runner tmp/episode_v9_audit.rb
#
# Run this after every 5-10 new episode analyses scored under v9+, or on demand.
# Checks three things per analysis:
#   1. Red flag literal_quote grounding — key present, not structurally missing
#   2. Dimension tier_check ↔ rating consistency (heuristic mismatch detection)
#   3. recommendation_basis is populated and non-empty
#
# Prints a brief quality report; flags anomalies for human review.

TIER_KEYWORDS = {
  "meets"         => ["meets", "meet"],
  "partially_meets" => ["partially", "partial"],
  "vague"         => ["vague"],
  "does_not_meet" => ["does not meet", "doesn't meet", "does_not_meet", "fails"]
}.freeze

DIMS = %w[relevance_discipline ownership_language outcome_orientation
          adaptability_signal communication_clarity].freeze

def tier_check_consistent?(tier_check_text, rating)
  return true if tier_check_text.blank?
  keywords = TIER_KEYWORDS[rating] || []
  text = tier_check_text.downcase
  # Check the first 80 chars — that's where the verdict normally appears
  opening = text[0, 80]
  keywords.any? { |kw| opening.include?(kw) }
end

# ── Filter: v9+ analyses only ─────────────────────────────────────────────────
scope = VideoAnalysis.where(status: "completed")
                     .where("prompt_version >= ?", "2026-06-17-v9")
                     .order(:id)

# Allow --since=VA_ID argument to audit only new records
if (since_arg = ARGV.find { |a| a.start_with?("--since=") })
  since_id = since_arg.split("=", 2).last.to_i
  scope = scope.where("id > ?", since_id)
end

analyses = scope.to_a

if analyses.empty?
  puts "No v9+ completed episode analyses found."
  exit
end

puts "Auditing #{analyses.size} v9+ episode analysis/analyses (prompt >= 2026-06-17-v9)."
puts "=" * 72

total_issues = 0

analyses.each do |va|
  fb      = va.structured_feedback || {}
  dims    = fb["episode_dimensions"] || {}
  flags   = Array(fb["red_flags"])
  rec_b   = fb["recommendation_basis"]
  issues  = []

  # ── 1. Red flag literal_quote grounding ─────────────────────────────────────
  flags.each_with_index do |flag, i|
    unless flag.is_a?(Hash)
      issues << "red_flags[#{i}]: legacy string shape — model reverted to flat string instead of {flag, literal_quote, rationale} object"
      next
    end
    if !flag.key?("literal_quote")
      issues << "red_flags[#{i}] '#{flag["flag"].to_s[0, 50]}': missing literal_quote key entirely — model skipped the grounding field"
    end
    if !flag.key?("rationale")
      issues << "red_flags[#{i}] '#{flag["flag"].to_s[0, 50]}': missing rationale key — model skipped explanation"
    end
    if flag.key?("literal_quote") && flag["literal_quote"].blank?
      issues << "red_flags[#{i}] '#{flag["flag"].to_s[0, 50]}': literal_quote is empty string (use \"NONE\" for absence-based flags)"
    end
  end

  # ── 2. Dimension tier_check ↔ rating consistency ────────────────────────────
  DIMS.each do |dim|
    raw = dims[dim]
    next if raw.nil?

    unless raw.is_a?(Hash)
      issues << "episode_dimensions.#{dim}: legacy flat string '#{raw}' — model reverted to v8 format"
      next
    end

    rating     = raw["rating"]
    tier_check = raw["tier_check"].to_s
    lq         = raw["literal_quote"]

    unless TIER_KEYWORDS.key?(raw["rating"].to_s)
      issues << "episode_dimensions.#{dim}: unknown rating value '#{rating}'"
    end

    if !tier_check_consistent?(tier_check, rating.to_s)
      issues << "episode_dimensions.#{dim}: tier_check opening doesn't clearly state '#{rating}' — possible reasoning/rating mismatch. Review: #{tier_check[0, 100].inspect}"
    end

    if !raw.key?("literal_quote")
      issues << "episode_dimensions.#{dim}: missing literal_quote key"
    elsif lq.blank? && lq != "NONE"
      issues << "episode_dimensions.#{dim}: literal_quote is blank (use \"NONE\" if nothing supports the rating)"
    end
  end

  # ── 3. recommendation_basis populated ───────────────────────────────────────
  if rec_b.nil?
    issues << "recommendation_basis: missing entirely — model omitted the field"
  elsif !rec_b.is_a?(Array)
    issues << "recommendation_basis: not an array (got #{rec_b.class})"
  elsif rec_b.empty?
    issues << "recommendation_basis: empty array — no decisive signals listed"
  elsif rec_b.size == 1
    issues << "recommendation_basis: only 1 item (expected 2-3 decisive signals)"
  end

  # ── Report ───────────────────────────────────────────────────────────────────
  status = issues.empty? ? "OK" : "#{issues.size} ISSUE(S)"
  puts "\nVA #{va.id} — #{va.display_name} [#{va.job_role&.title}] [#{va.prompt_version}]"
  puts "  rec=#{fb["recommendation"]}  score=#{va.score}  flags=#{flags.size}  dims_present=#{DIMS.count { |d| dims[d].is_a?(Hash) }}/5  →  #{status}"

  issues.each { |issue| puts "  ⚠ #{issue}" }
  total_issues += issues.size
end

puts "\n" + "=" * 72
puts "SUMMARY: #{analyses.size} analyses audited, #{total_issues} total issue(s) flagged."
puts analyses.size > 0 ? "Last VA audited: #{analyses.last.id} (use --since=#{analyses.last.id} to audit only new records next time)" : ""
puts "=" * 72
