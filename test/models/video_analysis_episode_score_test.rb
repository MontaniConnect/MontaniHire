require "test_helper"

class VideoAnalysisEpisodeScoreTest < ActiveSupport::TestCase
  DIMS = VideoAnalysis::EPISODE_WEIGHTS.keys.freeze

  def va_with_dims(dims, job_role: nil)
    va = VideoAnalysis.new
    va.structured_feedback = { "episode_dimensions" => dims }
    va.job_role = job_role if job_role
    va
  end

  def role_with_weights(weights)
    role = JobRole.new
    role.score_weights = weights
    role
  end

  # ── nil / missing dimensions ───────────────────────────────────────────────

  test "returns nil when structured_feedback is nil" do
    va = VideoAnalysis.new
    assert_nil va.episode_score
  end

  test "returns nil when episode_dimensions is absent" do
    va = VideoAnalysis.new
    va.structured_feedback = {}
    assert_nil va.episode_score
  end

  # ── falls back to system defaults when job_role is nil ────────────────────

  test "uses system default weights when job_role is nil" do
    dims = DIMS.index_with { "meets" }
    va   = va_with_dims(dims, job_role: nil)
    assert_equal 10.0, va.episode_score
  end

  test "system default weights match VideoAnalysis::EPISODE_WEIGHTS" do
    # outcome_orientation does_not_meet with default weights (outcome=30%):
    # raw = 0.20+0.10+0.00+0.25+0.15 = 0.70, weight = 1.00 → 7.0
    dims = DIMS.index_with("meets").merge("outcome_orientation" => "does_not_meet")
    va   = va_with_dims(dims, job_role: nil)
    assert_equal 7.0, va.episode_score
  end

  # ── uses job role custom weights when present ──────────────────────────────

  test "uses job role custom weights when job_role has score_weights set" do
    # Equal weights (20% each), outcome_orientation does_not_meet:
    # raw = 4*0.20*1.0 + 1*0.20*0.0 = 0.80, weight = 1.00 → 8.0
    # (default weights would give 7.0 — verifiable above)
    equal = DIMS.index_with { 20 }
    dims  = DIMS.index_with("meets").merge("outcome_orientation" => "does_not_meet")
    va    = va_with_dims(dims, job_role: role_with_weights(equal))
    assert_equal 8.0, va.episode_score
  end

  test "job role with empty score_weights falls back to system defaults" do
    dims = DIMS.index_with { "meets" }
    va   = va_with_dims(dims, job_role: role_with_weights({}))
    assert_equal 10.0, va.episode_score
  end

  test "custom weights produce a different score than defaults for the same dimensions" do
    dims           = DIMS.index_with("meets").merge("outcome_orientation" => "does_not_meet")
    default_score  = va_with_dims(dims, job_role: nil).episode_score
    equal          = DIMS.index_with { 20 }
    custom_score   = va_with_dims(dims, job_role: role_with_weights(equal)).episode_score
    assert_not_equal default_score, custom_score
    assert_equal 7.0, default_score
    assert_equal 8.0, custom_score
  end
end
