# Looks for a Google Meet auto-generated transcript (.vtt) in the same Drive
# folder as the recording, downloads it, and returns plain text.
# Returns nil if no transcript file is found or if the user has no OAuth token.
class MeetTranscriptService
  FOLDER_MIME = "application/vnd.google-apps.folder".freeze
  VTT_MIME    = TranscriptParsers::Vtt::MIME_TYPE
  DOCX_MIME   = TranscriptParsers::Docx::MIME_TYPE

  def initialize(analysis:)
    @analysis = analysis
  end

  def call
    return nil unless @analysis.user&.google_connected?
    return nil if @analysis.drive_file_id.blank?

    drive = GoogleDriveClient.for(@analysis.user)
    folder_id = resolve_folder_id(drive)
    return nil unless folder_id

    transcript_file = find_transcript(drive, folder_id)
    return nil unless transcript_file

    result = download_and_parse(drive, transcript_file)
    @analysis.update_columns(transcript_segments: result[:segments]) if result[:segments].any?
    result[:text]
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
    raw      = buf.string
    parser   = TranscriptParsers.for(file.mime_type)
    text     = parser.parse(raw)
    segments = file.mime_type == VTT_MIME ? parser.parse_segments(raw) : []
    { text: text, segments: segments }
  end
end
