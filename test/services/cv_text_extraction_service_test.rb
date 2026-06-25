require "test_helper"

class CvTextExtractionServiceTest < ActiveSupport::TestCase
  # ── Fake docx document structure ──────────────────────────────────────────

  FakeParagraph = Struct.new(:text) do
    def to_s = text
  end

  FakeCell  = Struct.new(:paragraphs)
  FakeRow   = Struct.new(:cells)
  FakeTable = Struct.new(:rows)
  FakeDoc   = Struct.new(:paragraphs, :tables)

  def service
    CvTextExtractionService.new(analysis: nil)
  end

  def with_docx(doc, &block)
    original = Docx::Document.method(:open)
    Docx::Document.define_singleton_method(:open) { |_path| doc }
    block.call
  ensure
    Docx::Document.define_singleton_method(:open, original)
  end

  def extract(doc)
    with_docx(doc) { service.send(:extract_docx, "irrelevant.docx") }
  end

  # ── paragraph extraction ──────────────────────────────────────────────────

  test "extracts text from top-level paragraphs" do
    doc = FakeDoc.new(
      [ FakeParagraph.new("John Smith"), FakeParagraph.new("Senior Engineer") ],
      []
    )
    result = extract(doc)
    assert_includes result, "John Smith"
    assert_includes result, "Senior Engineer"
  end

  # ── table cell extraction ─────────────────────────────────────────────────

  test "extracts text from table cells" do
    cell_para = FakeParagraph.new("Python · Rails · PostgreSQL")
    doc = FakeDoc.new(
      [],
      [ FakeTable.new([ FakeRow.new([ FakeCell.new([ cell_para ]) ]) ]) ]
    )
    result = extract(doc)
    assert_includes result, "Python · Rails · PostgreSQL"
  end

  test "extracts text from both paragraphs and table cells" do
    doc = FakeDoc.new(
      [ FakeParagraph.new("Jane Doe") ],
      [ FakeTable.new([ FakeRow.new([ FakeCell.new([ FakeParagraph.new("5 years at Acme Corp") ]) ]) ]) ]
    )
    result = extract(doc)
    assert_includes result, "Jane Doe"
    assert_includes result, "5 years at Acme Corp"
  end

  test "handles multiple rows and cells in a table" do
    row1 = FakeRow.new([
      FakeCell.new([ FakeParagraph.new("Role: Engineer") ]),
      FakeCell.new([ FakeParagraph.new("2019 – 2023") ])
    ])
    row2 = FakeRow.new([
      FakeCell.new([ FakeParagraph.new("Role: Lead") ]),
      FakeCell.new([ FakeParagraph.new("2023 – present") ])
    ])
    doc = FakeDoc.new([], [ FakeTable.new([ row1, row2 ]) ])
    result = extract(doc)
    assert_includes result, "Role: Engineer"
    assert_includes result, "2019 – 2023"
    assert_includes result, "Role: Lead"
    assert_includes result, "2023 – present"
  end

  test "omits empty paragraphs from output" do
    doc = FakeDoc.new(
      [ FakeParagraph.new(""), FakeParagraph.new("Real Content") ],
      [ FakeTable.new([ FakeRow.new([ FakeCell.new([ FakeParagraph.new("") ]) ]) ]) ]
    )
    result = extract(doc)
    assert_includes result, "Real Content"
    refute_match(/\A\n/, result)
  end
end
