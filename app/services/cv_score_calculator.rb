class CvScoreCalculator
  BASE_MAX    = 8.0
  ADJ_MAX     = 1.5
  NH_CAP      = 0.5
  SCORE_MAX   = 10.0

  GROWTH_BONUSES   = { "exceptional" => 0.50, "solid" => 0.25 }.freeze
  OWNERSHIP_BONUSES = { "high_ownership" => 0.50, "moderate_ownership" => 0.25 }.freeze
  LEVERAGE_BONUSES  = { "multiplier" => 0.50, "contributor" => 0.25 }.freeze

  def initialize(structured_feedback:)
    @sf = structured_feedback
  end

  def base_score
    reqs = Array(@sf["cv_requirements_coverage"])
    n_tot = reqs.size
    return 0.0 if n_tot.zero?

    n_ev  = reqs.count { |r| r["coverage"] == "evidenced" }
    n_par = reqs.count { |r| r["coverage"] == "partial" }
    ((n_ev * 1.0 + n_par * 0.5) / n_tot * BASE_MAX).round(2)
  end

  def adjustments
    {
      "growth_bonus"    => GROWTH_BONUSES.fetch(@sf["growth_curve"].to_s, 0.0),
      "ownership_bonus" => OWNERSHIP_BONUSES.fetch(@sf["tenure_ownership"].to_s, 0.0),
      "leverage_bonus"  => LEVERAGE_BONUSES.fetch(@sf["leverage"].to_s, 0.0)
    }
  end

  def nice_to_have_bonus
    nh = Array(@sf["nice_to_have_requirements_coverage"])
    raw = nh.sum do |r|
      case r["coverage"]
      when "evidenced" then 0.5
      when "partial"   then 0.25
      else 0.0
      end
    end
    [raw, NH_CAP].min.round(2)
  end

  def total_score
    result = base_score + adjustments.values.sum + nice_to_have_bonus
    [[result, SCORE_MAX].min, 0.0].max.round(1)
  end
end
