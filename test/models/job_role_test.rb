require "test_helper"

class JobRoleTest < ActiveSupport::TestCase
  def build_role(score_weights: {})
    user = build_user
    JobRole.new(
      user:             user,
      organization:     user.organization,
      title:            "Test Role",
      experience_level: "mid",
      required_skills:  "CRM experience",
      responsibilities: "Manage pipeline",
      score_weights:    score_weights
    )
  end

  # ── score_weights_with_defaults ────────────────────────────────────────────

  test "score_weights_with_defaults returns system defaults when score_weights is empty" do
    role = build_role(score_weights: {})
    assert_equal JobRole::DEFAULT_SCORE_WEIGHTS, role.score_weights_with_defaults
    assert_equal 100, role.score_weights_with_defaults.values.sum
  end

  test "score_weights_with_defaults returns custom weights when all keys are set" do
    custom = {
      "relevance_discipline"  => 25,
      "ownership_language"    => 15,
      "outcome_orientation"   => 25,
      "adaptability_signal"   => 20,
      "communication_clarity" => 15
    }
    role = build_role(score_weights: custom)
    assert_equal custom, role.score_weights_with_defaults
  end

  test "score_weights_with_defaults converts string values to integers" do
    role = build_role(score_weights: JobRole::DEFAULT_SCORE_WEIGHTS.transform_values(&:to_s))
    result = role.score_weights_with_defaults
    assert result.values.all? { |v| v.is_a?(Integer) }
  end

  # ── validation ─────────────────────────────────────────────────────────────

  test "validation passes when score_weights is empty" do
    role = build_role(score_weights: {})
    role.valid?
    assert_empty role.errors[:score_weights]
  end

  test "validation accepts weights that sum to exactly 100 with all keys present" do
    valid = {
      "relevance_discipline"  => 25,
      "ownership_language"    => 15,
      "outcome_orientation"   => 25,
      "adaptability_signal"   => 20,
      "communication_clarity" => 15
    }
    role = build_role(score_weights: valid)
    role.valid?
    assert_empty role.errors[:score_weights]
  end

  test "validation rejects weights that don't sum to 100" do
    bad = {
      "relevance_discipline"  => 30,
      "ownership_language"    => 30,
      "outcome_orientation"   => 30,
      "adaptability_signal"   => 30,
      "communication_clarity" => 30
    }
    role = build_role(score_weights: bad)
    role.valid?
    assert role.errors[:score_weights].any? { |e| e.include?("100") }
  end

  test "validation rejects weights with missing dimension keys" do
    incomplete = { "relevance_discipline" => 50, "ownership_language" => 50 }
    role = build_role(score_weights: incomplete)
    role.valid?
    assert role.errors[:score_weights].any?
  end

  test "validation rejects weights with all keys present but wrong sum" do
    wrong_sum = JobRole::DEFAULT_SCORE_WEIGHTS.merge("relevance_discipline" => 999)
    role = build_role(score_weights: wrong_sum)
    role.valid?
    assert role.errors[:score_weights].any? { |e| e.include?("100") }
  end
end
