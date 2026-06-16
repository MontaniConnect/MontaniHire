require "test_helper"

class EpisodeScoreCalculatorTest < ActiveSupport::TestCase
  # Weights: relevance_discipline=0.20, ownership_language=0.10,
  #          outcome_orientation=0.30, adaptability_signal=0.25,
  #          communication_clarity=0.15
  # Level values (same for all dims): meets=1.0, partially_meets=0.7,
  #                                   vague=0.4, does_not_meet=0.0

  ALL_DIMS = VideoAnalysis::EPISODE_WEIGHTS.keys.freeze

  def all_at(level)
    EpisodeScoreCalculator.new(dimensions: ALL_DIMS.index_with { level })
  end

  def calc(dimensions)
    EpisodeScoreCalculator.new(dimensions: dimensions)
  end

  # ── nil / empty input ──────────────────────────────────────────────────────

  test "returns nil when dimensions is nil" do
    assert_nil EpisodeScoreCalculator.new(dimensions: nil).total_score
  end

  test "returns nil when dimensions is empty" do
    assert_nil calc({}).total_score
  end

  test "returns nil when all provided levels are unknown" do
    assert_nil calc("outcome_orientation" => "unknown_level", "adaptability_signal" => "bogus").total_score
  end

  # ── uniform level scores ───────────────────────────────────────────────────

  test "returns 10.0 when all five dimensions are meets" do
    assert_equal 10.0, all_at("meets").total_score
  end

  test "returns 7.0 when all five dimensions are partially_meets" do
    assert_equal 7.0, all_at("partially_meets").total_score
  end

  test "returns 4.0 when all five dimensions are vague" do
    assert_equal 4.0, all_at("vague").total_score
  end

  test "returns 0.0 when all five dimensions are does_not_meet" do
    assert_equal 0.0, all_at("does_not_meet").total_score
  end

  # ── partial dimension sets ─────────────────────────────────────────────────

  test "scales to 10.0 when only one dimension is provided at meets" do
    # Only outcome_orientation meets (w=0.30): raw=0.30, weight=0.30 → 10.0
    assert_equal 10.0, calc("outcome_orientation" => "meets").total_score
  end

  test "scales to 10.0 when a single unknown dimension is mixed with a known meets" do
    # outcome_orientation meets contributes; unknown dimension is skipped
    result = calc("outcome_orientation" => "meets", "adaptability_signal" => "unknown").total_score
    assert_equal 10.0, result
  end

  # ── mixed-level weighted average ───────────────────────────────────────────

  test "computes weighted average for two dimensions at different levels" do
    # outcome_orientation meets (1.0, w=0.30) + communication_clarity does_not_meet (0.0, w=0.15)
    # total_raw = 0.30 + 0.0 = 0.30, total_weight = 0.45
    # score = (0.30 / 0.45) * 10 = 6.7
    result = calc("outcome_orientation" => "meets", "communication_clarity" => "does_not_meet").total_score
    assert_equal 6.7, result
  end

  test "computes weighted average for two dimensions at partially_meets and vague" do
    # relevance_discipline partially_meets (0.7, w=0.20) + ownership_language vague (0.4, w=0.10)
    # total_raw = 0.14 + 0.04 = 0.18, total_weight = 0.30
    # score = (0.18 / 0.30) * 10 = 6.0
    result = calc("relevance_discipline" => "partially_meets", "ownership_language" => "vague").total_score
    assert_equal 6.0, result
  end

  # ── rounding ───────────────────────────────────────────────────────────────

  test "rounds to one decimal place" do
    # adaptability_signal meets (1.0, w=0.25) + ownership_language does_not_meet (0.0, w=0.10)
    # total_raw = 0.25, total_weight = 0.35
    # score = (0.25/0.35)*10 = 7.142... → 7.1
    result = calc("adaptability_signal" => "meets", "ownership_language" => "does_not_meet").total_score
    assert_equal 7.1, result
  end

  # ── hash-format dimensions (new prompt format) ─────────────────────────────

  test "handles hash-format dimensions with rating and note keys" do
    dims = ALL_DIMS.index_with { { "rating" => "meets", "note" => "some evaluator note" } }
    assert_equal 10.0, EpisodeScoreCalculator.new(dimensions: dims).total_score
  end

  test "handles mixed plain-string and hash-format dimensions" do
    # outcome_orientation hash meets (1.0, w=0.30) + communication_clarity plain partially_meets (0.7, w=0.15)
    # total_raw = 0.30 + 0.105 = 0.405, total_weight = 0.45
    # score = (0.405 / 0.45) * 10 = 9.0
    result = calc(
      "outcome_orientation"   => { "rating" => "meets", "note" => "driven by results" },
      "communication_clarity" => "partially_meets"
    ).total_score
    assert_equal 9.0, result
  end

  test "returns nil when hash dimensions have no rating key" do
    assert_nil calc("outcome_orientation" => { "note" => "no rating present" }).total_score
  end
end
