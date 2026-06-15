class JdFitScoreCalculator
  SCORE_MAX = 10.0

  def initialize(coverage:)
    @reqs = Array(coverage)
  end

  def score
    n_tot = @reqs.size
    return nil if n_tot.zero?

    n_addr = @reqs.count { |r| r["coverage"] == "addressed" }
    n_par  = @reqs.count { |r| r["coverage"] == "partial" }
    ((n_addr * 1.0 + n_par * 0.5) / n_tot * SCORE_MAX).round(1)
  end
end
