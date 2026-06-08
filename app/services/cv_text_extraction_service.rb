require "pdf-reader"
require "docx"
require "tempfile"

class CvTextExtractionService
  def initialize(analysis)
    @analysis = analysis
  end

  def call
    @analysis.transition_to!("extracting")

    tmp = download_cv
    text = extract_text(tmp.path, @analysis.cv.filename.to_s)
    raise "Could not extract text from CV" if text.blank?

    @analysis.update!(extracted_text: text)
    text
  ensure
    tmp&.close
    tmp&.unlink
  end

  private

  def download_cv
    ext = File.extname(@analysis.cv.filename.to_s)
    tmp = Tempfile.new(["cv", ext], binmode: true)
    @analysis.cv.download { |chunk| tmp.write(chunk) }
    tmp.rewind
    tmp
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
