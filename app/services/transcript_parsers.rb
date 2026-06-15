module TranscriptParsers
  class Vtt
    MIME_TYPE = "text/vtt".freeze

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
  end

  class Docx
    MIME_TYPE = "application/vnd.openxmlformats-officedocument.wordprocessingml.document".freeze

    def parse(raw)
      require "docx"
      tmp = Tempfile.new(["transcript", ".docx"], binmode: true)
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
