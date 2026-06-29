class SegmentHighlightService
  MODEL        = "claude-haiku-4-5-20251001"
  MAX_SEGMENTS = 300

  SYSTEM_PROMPT = <<~PROMPT.strip.freeze
    You select transcript segments that best illustrate why a candidate scored as they did.
    Return only valid JSON: {"highlight_indices": [n, n, n, n]} — 3 to 4 integers.
    No markdown, no explanation.
  PROMPT

  def initialize(analysis:, client: AnthropicClient.new)
    @analysis = analysis
    @client   = client
  end

  def call
    segments = Array(@analysis.transcript_segments)
    fb       = @analysis.structured_feedback
    return [] if segments.blank? || fb.blank? || @analysis.episode_score.blank?

    indices = select_indices(segments, fb)
    @analysis.update_columns(highlight_indices: indices) if indices.any?
    indices
  rescue => e
    Rails.logger.warn "[SegmentHighlightService] #{e.class}: #{e.message}"
    []
  end

  private

  def select_indices(segments, fb)
    result = @client.complete(
      model:      MODEL,
      system:     [ { type: "text", text: SYSTEM_PROMPT } ],
      messages:   [ { role: "user", content: build_prompt(segments, fb) } ],
      max_tokens: 64
    )
    Array(result["highlight_indices"]).first(4).map(&:to_i)
  end

  def build_prompt(segments, fb)
    dims = fb["episode_dimensions"] || {}

    dim_lines = VideoAnalysis::EPISODE_WEIGHTS.map do |key, weight|
      rating = dims[key]
      rating = rating.is_a?(Hash) ? (rating["rating"] || rating.values.first) : rating
      "  #{key} (#{(weight * 100).to_i}%): #{rating}"
    end.join("\n")

    capped    = segments.first(MAX_SEGMENTS)
    seg_lines = capped.each_with_index.map do |s, i|
      "[#{i}] #{format_ts(s["start"])} #{s["text"].to_s.strip}"
    end.join("\n")

    <<~MSG.strip
      Episode Score: #{@analysis.episode_score}/10 — #{fb["recommendation"]}
      Summary: #{@analysis.summary}

      Episode Dimensions:
      #{dim_lines}

      Transcript (#{capped.size} segments):
      #{seg_lines}

      Select 3-4 indices (0 to #{capped.size - 1}) that most clearly show WHY this candidate scored this way. Prioritise the highest-weighted dimensions with clear meets/does_not_meet ratings. Avoid consecutive segments covering the same answer.
    MSG
  end

  def format_ts(seconds)
    return "0:00" unless seconds
    m = (seconds.to_f / 60).to_i
    s = (seconds.to_f % 60).to_i
    format("%d:%02d", m, s)
  end
end
