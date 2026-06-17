require "test_helper"

class SegmentHighlightServiceTest < ActiveSupport::TestCase
  SAMPLE_SEGMENTS = [
    { "start" => 0.0,  "end" => 3.5,  "text" => "Tell me about yourself." },
    { "start" => 3.5,  "end" => 12.0, "text" => "I led a team that increased revenue by 40%." },
    { "start" => 12.0, "end" => 18.0, "text" => "We had to pivot the strategy mid-project." },
    { "start" => 18.0, "end" => 25.0, "text" => "The outcome was a successful launch." },
    { "start" => 25.0, "end" => 30.0, "text" => "I am passionate about learning." }
  ].freeze

  SAMPLE_FEEDBACK = {
    "recommendation"   => "recommend",
    "episode_dimensions" => {
      "outcome_orientation"   => "meets",
      "adaptability_signal"   => "partially_meets",
      "relevance_discipline"  => "meets",
      "ownership_language"    => "partially_meets",
      "communication_clarity" => "vague"
    }
  }.freeze

  class FakeAnalysis
    attr_reader :transcript_segments, :structured_feedback, :score, :summary, :stored_indices

    def initialize(segments: SAMPLE_SEGMENTS, feedback: SAMPLE_FEEDBACK, score: 7.5)
      @transcript_segments = segments
      @structured_feedback = feedback
      @score               = score
      @summary             = "Strong outcome orientation, weak communication structure."
      @stored_indices      = nil
    end

    def update_columns(attrs)
      @stored_indices = attrs[:highlight_indices] if attrs.key?(:highlight_indices)
    end
  end

  def fake_client(response_indices)
    client = Object.new
    client.define_singleton_method(:complete) { |**_| { "highlight_indices" => response_indices } }
    client
  end

  def exploding_client
    client = Object.new
    client.define_singleton_method(:complete) { |**_| raise "Claude API timeout" }
    client
  end

  # ── Guard rails ────────────────────────────────────────────────────────────

  test "returns empty array when transcript_segments is blank" do
    analysis = FakeAnalysis.new(segments: [])
    result   = SegmentHighlightService.new(analysis: analysis, client: fake_client([1, 2])).call
    assert_equal [], result
  end

  test "returns empty array when structured_feedback is blank" do
    analysis = FakeAnalysis.new(feedback: nil)
    result   = SegmentHighlightService.new(analysis: analysis, client: fake_client([1, 2])).call
    assert_equal [], result
  end

  test "returns empty array when score is blank" do
    analysis = FakeAnalysis.new(score: nil)
    result   = SegmentHighlightService.new(analysis: analysis, client: fake_client([1, 2])).call
    assert_equal [], result
  end

  # ── Normal operation ───────────────────────────────────────────────────────

  test "returns highlight indices from Claude and stores them" do
    analysis = FakeAnalysis.new
    result   = SegmentHighlightService.new(analysis: analysis, client: fake_client([1, 2, 4])).call
    assert_equal [1, 2, 4], result
    assert_equal [1, 2, 4], analysis.stored_indices
  end

  test "clamps to maximum 4 returned indices" do
    analysis = FakeAnalysis.new
    result   = SegmentHighlightService.new(analysis: analysis, client: fake_client([0, 1, 2, 3, 4])).call
    assert result.size <= 4
  end

  test "maps returned values to integers" do
    analysis = FakeAnalysis.new
    result   = SegmentHighlightService.new(analysis: analysis, client: fake_client(["1", "3"])).call
    assert_equal [Integer, Integer], result.map(&:class)
  end

  # ── Error isolation ────────────────────────────────────────────────────────

  test "returns empty array and logs warning when Claude call raises" do
    analysis = FakeAnalysis.new
    logged   = nil
    Rails.logger.define_singleton_method(:warn) { |msg| logged = msg }

    result = SegmentHighlightService.new(analysis: analysis, client: exploding_client).call

    assert_equal [], result
    assert_match(/SegmentHighlightService/, logged.to_s)
  ensure
    Rails.logger.singleton_class.remove_method(:warn) rescue nil
  end

  test "does not update highlight_indices when call raises" do
    analysis = FakeAnalysis.new
    SegmentHighlightService.new(analysis: analysis, client: exploding_client).call
    assert_nil analysis.stored_indices
  end
end
