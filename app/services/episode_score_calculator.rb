class EpisodeScoreCalculator
  WEIGHTS = VideoAnalysis::EPISODE_WEIGHTS
  LEVEL_VALUES = VideoAnalysis::EPISODE_LEVEL_VALUES

  def initialize(dimensions:)
    @dims = dimensions || {}
  end

  def total_score
    total_weight = 0.0
    total_raw    = 0.0

    WEIGHTS.each do |dim, weight|
      raw   = @dims[dim]
      next unless raw.present?
      level = raw.is_a?(Hash) ? (raw["rating"] || raw.values.first) : raw
      next unless level.is_a?(String) && level.present?
      value = LEVEL_VALUES.dig(dim, level)
      next unless value
      total_raw    += value * weight
      total_weight += weight
    end

    return nil if total_weight.zero?
    (total_raw / total_weight * 10).round(1)
  end
end
