# Looks for a Google Meet auto-generated transcript (.vtt) in the same Drive
# folder as the recording, downloads it, and returns plain text.
# Returns nil if no transcript file is found or if the user has no OAuth token.
class MeetTranscriptService
  VTT_MIME  = "text/vtt".freeze
  DOCX_MIME = "application/vnd.openxmlformats-officedocument.wordprocessingml.document".freeze

  def initialize(analysis)
    @analysis = analysis
  end

  FOLDER_MIME = "application/vnd.google-apps.folder".freeze

  def call
    return nil unless @analysis.user&.google_connected?
    return nil if @analysis.drive_file_id.blank?

    drive = GoogleDriveClient.for(@analysis.user)
    folder_id = resolve_folder_id(drive)
    return nil unless folder_id

    transcript_file = find_transcript(drive, folder_id)
    return nil unless transcript_file

    download_and_parse(drive, transcript_file)
  rescue => e
    Rails.logger.warn "[MeetTranscriptService] #{e.class}: #{e.message}"
    nil
  end

  private

  def resolve_folder_id(drive)
    meta = drive.get_file(@analysis.drive_file_id, fields: "parents,name,mimeType")
    @recording_name = meta.name
    if meta.mime_type == FOLDER_MIME
      @analysis.drive_file_id
    else
      meta.parents&.first
    end
  end

  def find_transcript(drive, parent_id)
    base_name = File.basename(@recording_name.to_s, ".*")

    # Google Meet stores the transcript with the same base name as the recording.
    # Try exact VTT match first, then DOCX, then any VTT in the folder.
    candidates = [
      "name = '#{base_name}.vtt' and '#{parent_id}' in parents and trashed = false",
      "name = '#{base_name}.docx' and '#{parent_id}' in parents and trashed = false",
      "mimeType = '#{VTT_MIME}' and '#{parent_id}' in parents and trashed = false"
    ]

    candidates.each do |q|
      result = drive.list_files(q: q, fields: "files(id,name,mimeType)", page_size: 1)
      return result.files.first if result.files.any?
    end

    nil
  end

  def download_and_parse(drive, file)
    buf = StringIO.new
    drive.get_file(file.id, download_dest: buf)
    raw = buf.string.force_encoding("UTF-8")

    case file.mime_type
    when VTT_MIME then parse_vtt(raw)
    when DOCX_MIME then parse_docx(raw)
    else raw.strip
    end
  end

  def parse_vtt(vtt)
    lines = vtt.lines.map(&:strip)
    text_lines = []
    lines.each do |line|
      next if line.start_with?("WEBVTT")
      next if line.match?(/^\d+$/)                      # cue index
      next if line.match?(/\d{2}:\d{2}:\d{2}/)         # timestamp
      next if line.empty?
      # Strip VTT markup tags like <00:00:01.000><c>
      clean = line.gsub(/<[^>]+>/, "").strip
      text_lines << clean if clean.present?
    end
    text_lines.uniq.join(" ").squish
  end

  def parse_docx(raw)
    require "docx"
    tmp = Tempfile.new(["transcript", ".docx"], binmode: true)
    tmp.write(raw)
    tmp.rewind
    doc = Docx::Document.open(tmp.path)
    doc.paragraphs.map(&:to_s).reject(&:blank?).join("\n")
  ensure
    tmp&.close
    tmp&.unlink
  end
end
