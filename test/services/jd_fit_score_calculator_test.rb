require "test_helper"

class JdFitScoreCalculatorTest < ActiveSupport::TestCase
  def calc(reqs)
    JdFitScoreCalculator.new(coverage: reqs)
  end

  def req(coverage)
    { "coverage" => coverage }
  end

  # ── nil / empty input ──────────────────────────────────────────────────────

  test "returns nil when coverage is nil" do
    assert_nil JdFitScoreCalculator.new(coverage: nil).score
  end

  test "returns nil when coverage is empty" do
    assert_nil calc([]).score
  end

  # ── uniform coverage scores ────────────────────────────────────────────────

  test "returns 10.0 when all requirements are addressed" do
    assert_equal 10.0, calc(Array.new(4) { req("addressed") }).score
  end

  test "returns 5.0 when all requirements are partial" do
    assert_equal 5.0, calc(Array.new(4) { req("partial") }).score
  end

  test "returns 0.0 when all requirements are not addressed" do
    assert_equal 0.0, calc(Array.new(3) { req("not addressed") }).score
  end

  # ── mixed coverage ─────────────────────────────────────────────────────────

  test "weights addressed at 1.0 and partial at 0.5" do
    # 3 addressed + 1 partial + 1 not_addressed = 5 total
    # (3*1.0 + 1*0.5) / 5 * 10 = 7.0
    reqs = [req("addressed"), req("addressed"), req("addressed"), req("partial"), req("not addressed")]
    assert_equal 7.0, calc(reqs).score
  end

  test "single addressed requirement returns 10.0" do
    assert_equal 10.0, calc([req("addressed")]).score
  end

  test "single partial requirement returns 5.0" do
    assert_equal 5.0, calc([req("partial")]).score
  end

  test "2 addressed and 2 not addressed returns 5.0" do
    reqs = [req("addressed"), req("addressed"), req("not addressed"), req("not addressed")]
    assert_equal 5.0, calc(reqs).score
  end

  # ── rounding ───────────────────────────────────────────────────────────────

  test "rounds to one decimal place" do
    # 1 addressed + 2 not_addressed = 3 total
    # (1.0 / 3) * 10 = 3.333... → 3.3
    reqs = [req("addressed"), req("not addressed"), req("not addressed")]
    assert_equal 3.3, calc(reqs).score
  end
end
