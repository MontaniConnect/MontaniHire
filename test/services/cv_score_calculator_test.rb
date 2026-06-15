require "test_helper"

class CvScoreCalculatorTest < ActiveSupport::TestCase
  def calc(overrides = {})
    CvScoreCalculator.new(structured_feedback: {
      "cv_requirements_coverage"         => [],
      "nice_to_have_requirements_coverage" => [],
      "growth_curve"   => nil,
      "tenure_ownership" => nil,
      "leverage"         => nil
    }.merge(overrides))
  end

  def req(coverage)
    { "coverage" => coverage }
  end

  # ── base_score ─────────────────────────────────────────────────────────────

  test "base_score returns 0.0 when coverage list is empty" do
    assert_equal 0.0, calc.base_score
  end

  test "base_score returns 0.0 when coverage list is nil" do
    assert_equal 0.0, CvScoreCalculator.new(structured_feedback: {}).base_score
  end

  test "base_score is 8.0 when all requirements are evidenced" do
    reqs = Array.new(4) { req("evidenced") }
    assert_equal 8.0, calc("cv_requirements_coverage" => reqs).base_score
  end

  test "base_score is 4.0 when all requirements are partial" do
    reqs = Array.new(4) { req("partial") }
    assert_equal 4.0, calc("cv_requirements_coverage" => reqs).base_score
  end

  test "base_score is 0.0 when all requirements are not evidenced" do
    reqs = Array.new(3) { req("not evidenced") }
    assert_equal 0.0, calc("cv_requirements_coverage" => reqs).base_score
  end

  test "base_score weights evidenced at 1.0 and partial at 0.5" do
    # 2 evidenced + 1 partial + 1 not evidenced = 4 total
    # (2*1.0 + 1*0.5) / 4 * 8.0 = 5.0
    reqs = [req("evidenced"), req("evidenced"), req("partial"), req("not evidenced")]
    assert_equal 5.0, calc("cv_requirements_coverage" => reqs).base_score
  end

  test "base_score rounds to 2 decimal places" do
    # 1 evidenced + 1 partial = 2 total
    # (1.0 + 0.5) / 2 * 8.0 = 6.0 (exact)
    reqs = [req("evidenced"), req("partial")]
    assert_equal 6.0, calc("cv_requirements_coverage" => reqs).base_score

    # 1 evidenced + 2 not_evidenced = 3 total
    # (1.0) / 3 * 8.0 = 2.666... → 2.67
    reqs2 = [req("evidenced"), req("not evidenced"), req("not evidenced")]
    assert_equal 2.67, calc("cv_requirements_coverage" => reqs2).base_score
  end

  # ── adjustments ────────────────────────────────────────────────────────────

  test "adjustments returns 0.0 for all bonuses when signals are absent" do
    result = calc.adjustments
    assert_equal({ "growth_bonus" => 0.0, "ownership_bonus" => 0.0, "leverage_bonus" => 0.0 }, result)
  end

  test "growth_bonus is 0.50 for exceptional and 0.25 for solid" do
    assert_equal 0.50, calc("growth_curve" => "exceptional").adjustments["growth_bonus"]
    assert_equal 0.25, calc("growth_curve" => "solid").adjustments["growth_bonus"]
    assert_equal 0.0,  calc("growth_curve" => "stagnant").adjustments["growth_bonus"]
    assert_equal 0.0,  calc("growth_curve" => "unknown").adjustments["growth_bonus"]
  end

  test "ownership_bonus is 0.50 for high_ownership and 0.25 for moderate_ownership" do
    assert_equal 0.50, calc("tenure_ownership" => "high_ownership").adjustments["ownership_bonus"]
    assert_equal 0.25, calc("tenure_ownership" => "moderate_ownership").adjustments["ownership_bonus"]
    assert_equal 0.0,  calc("tenure_ownership" => "flight_risk").adjustments["ownership_bonus"]
  end

  test "leverage_bonus is 0.50 for multiplier and 0.25 for contributor" do
    assert_equal 0.50, calc("leverage" => "multiplier").adjustments["leverage_bonus"]
    assert_equal 0.25, calc("leverage" => "contributor").adjustments["leverage_bonus"]
    assert_equal 0.0,  calc("leverage" => "solitary").adjustments["leverage_bonus"]
  end

  # ── nice_to_have_bonus ─────────────────────────────────────────────────────

  test "nice_to_have_bonus is 0.0 when list is empty" do
    assert_equal 0.0, calc.nice_to_have_bonus
  end

  test "nice_to_have_bonus counts evidenced as 0.5 and partial as 0.25" do
    one_evidenced = calc("nice_to_have_requirements_coverage" => [req("evidenced")])
    assert_equal 0.5, one_evidenced.nice_to_have_bonus

    one_partial = calc("nice_to_have_requirements_coverage" => [req("partial")])
    assert_equal 0.25, one_partial.nice_to_have_bonus
  end

  test "nice_to_have_bonus is capped at 0.5" do
    many = Array.new(4) { req("evidenced") }
    assert_equal 0.5, calc("nice_to_have_requirements_coverage" => many).nice_to_have_bonus
  end

  test "nice_to_have_bonus ignores not evidenced entries" do
    reqs = [req("not evidenced"), req("not evidenced")]
    assert_equal 0.0, calc("nice_to_have_requirements_coverage" => reqs).nice_to_have_bonus
  end

  # ── total_score ────────────────────────────────────────────────────────────

  test "total_score is 0.0 when all inputs are zero" do
    assert_equal 0.0, calc.total_score
  end

  test "total_score is capped at 10.0" do
    # Max possible: 8.0 base + 0.5 growth + 0.5 ownership + 0.5 leverage + 0.5 nh = 10.0
    reqs = Array.new(4) { req("evidenced") }
    nh   = Array.new(4) { req("evidenced") }
    c = calc(
      "cv_requirements_coverage"           => reqs,
      "nice_to_have_requirements_coverage" => nh,
      "growth_curve"    => "exceptional",
      "tenure_ownership" => "high_ownership",
      "leverage"         => "multiplier"
    )
    assert_equal 10.0, c.total_score
  end

  test "total_score sums base, adjustments, and nice_to_have correctly" do
    # base: (2*1.0 + 1*0.5) / 4 * 8.0 = 5.0
    # adjustments: solid(0.25) + moderate_ownership(0.25) + contributor(0.25) = 0.75
    # nice_to_have: 1 partial = 0.25
    # total: 5.0 + 0.75 + 0.25 = 6.0
    reqs = [req("evidenced"), req("evidenced"), req("partial"), req("not evidenced")]
    nh   = [req("partial")]
    c = calc(
      "cv_requirements_coverage"           => reqs,
      "nice_to_have_requirements_coverage" => nh,
      "growth_curve"     => "solid",
      "tenure_ownership" => "moderate_ownership",
      "leverage"         => "contributor"
    )
    assert_equal 6.0, c.total_score
  end

  test "total_score is never negative" do
    assert_equal 0.0, calc("growth_curve" => nil).total_score
  end
end
