require "test_helper"

class TranscriptParsersTest < ActiveSupport::TestCase
  # ── TranscriptParsers.for (registry) ──────────────────────────────────────

  test ".for returns a Vtt instance for the VTT mime type" do
    parser = TranscriptParsers.for("text/vtt")
    assert_instance_of TranscriptParsers::Vtt, parser
  end

  test ".for returns a Docx instance for the DOCX mime type" do
    parser = TranscriptParsers.for("application/vnd.openxmlformats-officedocument.wordprocessingml.document")
    assert_instance_of TranscriptParsers::Docx, parser
  end

  test ".for returns a PlainText instance for unknown mime types" do
    assert_instance_of TranscriptParsers::PlainText, TranscriptParsers.for("text/plain")
    assert_instance_of TranscriptParsers::PlainText, TranscriptParsers.for("video/mp4")
    assert_instance_of TranscriptParsers::PlainText, TranscriptParsers.for("")
  end

  test "all registered parsers respond to #parse" do
    [
      TranscriptParsers::Vtt.new,
      TranscriptParsers::PlainText.new
    ].each do |parser|
      assert_respond_to parser, :parse
    end
  end

  # ── TranscriptParsers::Vtt ─────────────────────────────────────────────────

  # Lines with embedded timestamps (e.g. <00:00:07.500><c>text</c>) are filtered
  # out by the timestamp check before tag stripping reaches them — by design.
  VTT_SAMPLE = <<~VTT
    WEBVTT

    1
    00:00:01.000 --> 00:00:03.000
    Hello world

    2
    00:00:03.500 --> 00:00:05.000
    Hello world

    3
    00:00:05.000 --> 00:00:07.000
    <c>Goodbye</c>
  VTT

  test "Vtt strips WEBVTT header line" do
    result = TranscriptParsers::Vtt.new.parse(VTT_SAMPLE)
    assert_not_includes result, "WEBVTT"
  end

  test "Vtt strips cue index lines" do
    result = TranscriptParsers::Vtt.new.parse(VTT_SAMPLE)
    # Standalone digits like "1", "2", "3" should not appear as tokens
    assert_no_match(/\A\d+\z/, result)
  end

  test "Vtt strips timestamp lines" do
    result = TranscriptParsers::Vtt.new.parse(VTT_SAMPLE)
    refute_match(/\d{2}:\d{2}:\d{2}/, result)
  end

  test "Vtt deduplicates repeated lines" do
    result = TranscriptParsers::Vtt.new.parse(VTT_SAMPLE)
    assert_equal 1, result.scan("Hello world").size
  end

  test "Vtt strips VTT markup tags from cue text" do
    result = TranscriptParsers::Vtt.new.parse(VTT_SAMPLE)
    refute_match(/<[^>]+>/, result)
    assert_includes result, "Goodbye"
  end

  test "Vtt returns empty string for blank input" do
    assert_equal "", TranscriptParsers::Vtt.new.parse("")
    assert_equal "", TranscriptParsers::Vtt.new.parse("WEBVTT\n\n")
  end

  test "Vtt joins text lines with spaces and squishes whitespace" do
    vtt = "WEBVTT\n\n1\n00:00:01.000 --> 00:00:02.000\nHello\n\n2\n00:00:02.000 --> 00:00:03.000\nworld\n"
    assert_equal "Hello world", TranscriptParsers::Vtt.new.parse(vtt)
  end

  test "Vtt handles binary-encoded input by forcing UTF-8" do
    raw = "WEBVTT\n\n1\n00:00:01.000 --> 00:00:02.000\nTest\n".b
    assert_equal "Test", TranscriptParsers::Vtt.new.parse(raw)
  end

  # ── TranscriptParsers::Vtt#parse_segments ─────────────────────────────────

  WHISPER_VTT = <<~VTT
    WEBVTT

    00:00:01.000 --> 00:00:03.500
     Hello, my name is John.

    00:00:03.500 --> 00:00:07.200
     I have five years of experience.

    00:00:07.200 --> 00:00:10.000
     <c>Goodbye</c> and thanks.
  VTT

  MEET_VTT = <<~VTT
    WEBVTT

    1
    00:00:00.000 --> 00:00:04.000
    Welcome to the interview.

    2
    00:00:04.000 --> 00:00:08.500
    Please introduce yourself.
  VTT

  test "parse_segments returns correct start/end/text from Whisper VTT" do
    segs = TranscriptParsers::Vtt.new.parse_segments(WHISPER_VTT)
    assert_equal 3, segs.size

    assert_in_delta 1.0,  segs[0]["start"], 0.001
    assert_in_delta 3.5,  segs[0]["end"],   0.001
    assert_equal "Hello, my name is John.", segs[0]["text"]

    assert_in_delta 3.5,  segs[1]["start"], 0.001
    assert_in_delta 7.2,  segs[1]["end"],   0.001
    assert_equal "I have five years of experience.", segs[1]["text"]
  end

  test "parse_segments strips VTT markup tags from segment text" do
    segs = TranscriptParsers::Vtt.new.parse_segments(WHISPER_VTT)
    assert_equal "Goodbye and thanks.", segs[2]["text"]
    refute_match(/<[^>]+>/, segs[2]["text"])
  end

  test "parse_segments handles Google Meet VTT with numeric cue IDs" do
    segs = TranscriptParsers::Vtt.new.parse_segments(MEET_VTT)
    assert_equal 2, segs.size
    assert_in_delta 0.0, segs[0]["start"], 0.001
    assert_in_delta 4.0, segs[0]["end"],   0.001
    assert_equal "Welcome to the interview.", segs[0]["text"]
  end

  test "parse_segments converts HH:MM:SS.mmm to float seconds correctly" do
    vtt = "WEBVTT\n\n01:02:03.456 --> 01:02:07.000\nText\n"
    segs = TranscriptParsers::Vtt.new.parse_segments(vtt)
    assert_equal 1, segs.size
    assert_in_delta 3723.456, segs[0]["start"], 0.001
  end

  test "parse_segments returns empty array for blank input" do
    assert_equal [], TranscriptParsers::Vtt.new.parse_segments("")
    assert_equal [], TranscriptParsers::Vtt.new.parse_segments("WEBVTT\n\n")
  end

  test "parse_segments returns string-keyed hashes (JSONB round-trip safe)" do
    segs = TranscriptParsers::Vtt.new.parse_segments(WHISPER_VTT)
    assert segs.first.key?("start"), "expected string key 'start'"
    assert segs.first.key?("end"),   "expected string key 'end'"
    assert segs.first.key?("text"),  "expected string key 'text'"
  end

  test "parse is unchanged by adding parse_segments — flat text regression" do
    result = TranscriptParsers::Vtt.new.parse(WHISPER_VTT)
    assert_kind_of String, result
    assert_includes result, "Hello, my name is John."
    assert_includes result, "I have five years of experience."
    assert_includes result, "Goodbye"
    refute_match(/\d{2}:\d{2}:\d{2}/, result)
  end

  # ── TranscriptParsers::PlainText ───────────────────────────────────────────

  test "PlainText returns stripped string" do
    assert_equal "hello", TranscriptParsers::PlainText.new.parse("  hello  ")
  end

  test "PlainText preserves interior content unchanged" do
    text = "line one\nline two\nline three"
    assert_equal text, TranscriptParsers::PlainText.new.parse(text)
  end

  test "PlainText handles binary-encoded input by forcing UTF-8" do
    raw = "transcript content".b
    result = TranscriptParsers::PlainText.new.parse(raw)
    assert_equal "transcript content", result
    assert_equal Encoding::UTF_8, result.encoding
  end

  test "PlainText returns empty string for blank input" do
    assert_equal "", TranscriptParsers::PlainText.new.parse("")
    assert_equal "", TranscriptParsers::PlainText.new.parse("   ")
  end
end
