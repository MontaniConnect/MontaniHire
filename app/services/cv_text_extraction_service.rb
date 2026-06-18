require "pdf-reader"
require "docx"
require "tempfile"

class CvTextExtractionService
  def initialize(analysis:)
    @analysis = analysis
  end

  def call
    @analysis.transition_to!("extracting")

    tmp, filename = download_cv
    text = extract_text(tmp.path, filename)
    raise "Could not extract text from CV" if text.blank?

    @analysis.update!(extracted_text: text)
    text
  ensure
    tmp&.close
    tmp&.unlink
  end

  private

  def download_cv
    if @analysis.drive_file_id.present?
      download_from_drive
    else
      download_from_storage
    end
  end

  def download_from_drive
    drive    = GoogleDriveClient.for(@analysis.user)
    meta     = drive.get_file(@analysis.drive_file_id, fields: "name,mimeType")
    filename = meta.name.presence || @analysis.drive_file_name.presence || "cv.pdf"
    @analysis.update!(drive_file_name: filename) if @analysis.drive_file_name.blank?

    ext = File.extname(filename).downcase.presence || ".pdf"
    tmp = Tempfile.new([ "cv", ext ], binmode: true)
    drive.get_file(@analysis.drive_file_id, download_dest: tmp)
    tmp.rewind
    [ tmp, filename ]
  end

  def download_from_storage
    filename = @analysis.cv.filename.to_s
    ext      = File.extname(filename)
    tmp      = Tempfile.new([ "cv", ext ], binmode: true)
    @analysis.cv.download { |chunk| tmp.write(chunk) }
    tmp.rewind
    [ tmp, filename ]
  end

  def extract_text(path, filename)
    case File.extname(filename).downcase
    when ".pdf"  then extract_pdf(path)
    when ".docx" then extract_docx(path)
    when ".txt"  then File.read(path)
    else raise "Unsupported file type: #{File.extname(filename)}. Use PDF, DOCX, or TXT."
    end
  end

  def extract_pdf(path)
    reader = PDF::Reader.new(path)
    reader.pages.map(&:text).join("\n").strip
  end

  def extract_docx(path)
    doc = Docx::Document.open(path)
    doc.paragraphs.map(&:to_s).join("\n").strip
  end
end
