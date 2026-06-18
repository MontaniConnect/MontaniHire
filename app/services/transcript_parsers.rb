module TranscriptParsers
  class Vtt
    MIME_TYPE    = "text/vtt".freeze
    TIMESTAMP_RE = /\A(\d{2}):(\d{2}):(\d{2})\.(\d{3})\s*-->\s*(\d{2}):(\d{2}):(\d{2})\.(\d{3})/.freeze

    def parse(raw)
      lines = raw.force_encoding("UTF-8").lines.map(&:strip)
      text_lines = []
      lines.each do |line|
        next if line.start_with?("WEBVTT")
        next if line.match?(/^\d+$/)
        next if line.match?(/\d{2}:\d{2}:\d{2}/)
        next if line.empty?
        clean = line.gsub(/<[^>]+>/, "").strip
        text_lines << clean if clean.present?
      end
      text_lines.uniq.join(" ").squish
    end

    def parse_segments(raw)
      lines    = raw.force_encoding("UTF-8").lines.map(&:strip)
      segments = []
      i = 0
      while i < lines.size
        if (m = lines[i].match(TIMESTAMP_RE))
          start_s = to_seconds(m[1], m[2], m[3], m[4])
          end_s   = to_seconds(m[5], m[6], m[7], m[8])
          i += 1
          parts = []
          while i < lines.size && lines[i] != "" && !lines[i].match?(TIMESTAMP_RE)
            clean = lines[i].gsub(/<[^>]+>/, "").strip
            parts << clean unless clean.empty?
            i += 1
          end
          text = parts.join(" ").squish
          segments << { "start" => start_s, "end" => end_s, "text" => text } if text.present?
        else
          i += 1
        end
      end
      segments
    end

    private

    def to_seconds(h, m, s, ms)
      h.to_i * 3600 + m.to_i * 60 + s.to_i + ms.to_i / 1000.0
    end
  end

  class Docx
    MIME_TYPE = "application/vnd.openxmlformats-officedocument.wordprocessingml.document".freeze

    def parse(raw)
      require "docx"
      tmp = Tempfile.new([ "transcript", ".docx" ], binmode: true)
      tmp.write(raw.force_encoding("UTF-8"))
      tmp.rewind
      doc = Docx::Document.open(tmp.path)
      doc.paragraphs.map(&:to_s).reject(&:blank?).join("\n")
    ensure
      tmp&.close
      tmp&.unlink
    end
  end

  class PlainText
    def parse(raw)
      raw.force_encoding("UTF-8").strip
    end
  end

  REGISTRY = {
    Vtt::MIME_TYPE  => Vtt.new,
    Docx::MIME_TYPE => Docx.new
  }.freeze

  def self.for(mime_type)
    REGISTRY.fetch(mime_type, PlainText.new)
  end
end
