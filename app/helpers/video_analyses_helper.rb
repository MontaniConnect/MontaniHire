module VideoAnalysesHelper
  def format_transcript_time(seconds)
    return "0:00" unless seconds
    total = seconds.to_f
    m = (total / 60).to_i
    s = (total % 60).to_i
    format("%d:%02d", m, s)
  end
end
