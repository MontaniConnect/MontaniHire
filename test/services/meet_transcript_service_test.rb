require "test_helper"

class MeetTranscriptServiceTest < ActiveSupport::TestCase
  SAMPLE_VTT = <<~VTT
    WEBVTT

    00:00:00.000 --> 00:00:03.500
    Tell me about yourself.

    00:00:03.500 --> 00:00:12.000
    I led a team that increased revenue by 40%.

    00:00:12.000 --> 00:00:18.000
    We had to pivot the strategy mid-project.
  VTT

  SAMPLE_DOCX_TEXT = "Plain text from a DOCX file."

  # ── Test doubles ──────────────────────────────────────────────────────────

  FakeFile = Struct.new(:id, :name, :mime_type, keyword_init: true)

  class FakeAnalysis
    attr_reader :updated_columns
    attr_accessor :drive_file_id

    def initialize(drive_file_id: "file123")
      @drive_file_id   = drive_file_id
      @updated_columns = {}
      @user            = FakeUser.new
    end

    def user = @user

    def update_columns(attrs)
      @updated_columns.merge!(attrs)
    end
  end

  class FakeUser
    def google_connected? = true
  end

  # Minimal fake Drive client.
  class FakeDrive
    def initialize(meta:, list_result:, raw_content:)
      @meta        = meta
      @list_result = list_result
      @raw_content = raw_content
    end

    def get_file(id, fields: nil, download_dest: nil)
      if download_dest
        download_dest.write(@raw_content)
        nil
      else
        @meta
      end
    end

    def list_files(q:, fields:, page_size:)
      @list_result
    end
  end

  FakeMeta   = Struct.new(:name, :mime_type, :parents, keyword_init: true)
  FakeList   = Struct.new(:files, keyword_init: true)

  VTT_MIME  = TranscriptParsers::Vtt::MIME_TYPE
  DOCX_MIME = TranscriptParsers::Docx::MIME_TYPE

  def vtt_meta(folder_id: "folder1")
    FakeMeta.new(name: "Interview Recording.vtt", mime_type: VTT_MIME, parents: [ folder_id ])
  end

  def recording_meta(folder_id: "folder1")
    FakeMeta.new(name: "Interview Recording", mime_type: "video/mp4", parents: [ folder_id ])
  end

  def vtt_file = FakeFile.new(id: "vtt1", name: "Interview Recording.vtt", mime_type: VTT_MIME)
  def docx_file = FakeFile.new(id: "docx1", name: "Interview Recording.docx", mime_type: DOCX_MIME)

  def build_service(analysis: FakeAnalysis.new, drive:)
    svc = MeetTranscriptService.new(analysis: analysis)
    svc.define_singleton_method(:build_drive) { drive } rescue nil
    # Inject drive via GoogleDriveClient stub on the singleton
    GoogleDriveClient.define_singleton_method(:for) { |_user| drive }
    svc
  end

  def teardown
    GoogleDriveClient.singleton_class.remove_method(:for) rescue nil
  end

  # ── Guard rails ─────────────────────────────────────────────────────────

  test "returns nil when user is not google connected" do
    analysis = FakeAnalysis.new
    analysis.user.define_singleton_method(:google_connected?) { false }

    svc = MeetTranscriptService.new(analysis: analysis)
    assert_nil svc.call
  end

  test "returns nil when drive_file_id is blank" do
    analysis = FakeAnalysis.new(drive_file_id: nil)
    assert_nil MeetTranscriptService.new(analysis: analysis).call
  end

  # ── VTT path ────────────────────────────────────────────────────────────

  test "returns plain text from a VTT transcript" do
    analysis = FakeAnalysis.new
    drive    = FakeDrive.new(
      meta:        recording_meta,
      list_result: FakeList.new(files: [ vtt_file ]),
      raw_content: SAMPLE_VTT
    )
    build_service(analysis: analysis, drive: drive)

    result = MeetTranscriptService.new(analysis: analysis).call

    assert_includes result, "Tell me about yourself"
    assert_includes result, "increased revenue by 40%"
  end

  test "writes transcript_segments when VTT has timestamps" do
    analysis = FakeAnalysis.new
    drive    = FakeDrive.new(
      meta:        recording_meta,
      list_result: FakeList.new(files: [ vtt_file ]),
      raw_content: SAMPLE_VTT
    )
    build_service(analysis: analysis, drive: drive)

    MeetTranscriptService.new(analysis: analysis).call

    segs = analysis.updated_columns[:transcript_segments]
    assert segs.present?, "expected transcript_segments to be written"
    assert_equal 3, segs.size
    assert_equal 0.0,  segs[0]["start"]
    assert_equal 3.5,  segs[0]["end"]
    assert_equal "Tell me about yourself.", segs[0]["text"]
  end

  test "segment start/end times are floats" do
    analysis = FakeAnalysis.new
    drive    = FakeDrive.new(
      meta:        recording_meta,
      list_result: FakeList.new(files: [ vtt_file ]),
      raw_content: SAMPLE_VTT
    )
    build_service(analysis: analysis, drive: drive)

    MeetTranscriptService.new(analysis: analysis).call

    segs = analysis.updated_columns[:transcript_segments]
    assert segs.all? { |s| s["start"].is_a?(Float) && s["end"].is_a?(Float) }
  end

  # ── DOCX path ───────────────────────────────────────────────────────────

  test "does not write transcript_segments for DOCX files" do
    analysis = FakeAnalysis.new
    drive    = FakeDrive.new(
      meta:        recording_meta,
      list_result: FakeList.new(files: [ docx_file ]),
      raw_content: "PK\x03\x04" # minimal non-empty DOCX stub
    )
    build_service(analysis: analysis, drive: drive)

    # DOCX parsing may raise; we only care that no segments column is written
    MeetTranscriptService.new(analysis: analysis).call rescue nil

    assert_not analysis.updated_columns.key?(:transcript_segments),
      "transcript_segments should not be written for non-VTT files"
  end

  # ── Error isolation ──────────────────────────────────────────────────────

  test "returns nil and logs warning when Drive raises" do
    analysis = FakeAnalysis.new
    boom_drive = Object.new
    boom_drive.define_singleton_method(:get_file) { |*_a, **_k| raise "Drive API timeout" }
    GoogleDriveClient.define_singleton_method(:for) { |_| boom_drive }

    logged = nil
    Rails.logger.define_singleton_method(:warn) { |msg| logged = msg }

    result = MeetTranscriptService.new(analysis: analysis).call

    assert_nil result
    assert_match(/MeetTranscriptService/, logged.to_s)
  ensure
    Rails.logger.singleton_class.remove_method(:warn) rescue nil
  end

  test "does not write transcript_segments when Drive raises" do
    analysis   = FakeAnalysis.new
    boom_drive = Object.new
    boom_drive.define_singleton_method(:get_file) { |*_a, **_k| raise "Drive API timeout" }
    GoogleDriveClient.define_singleton_method(:for) { |_| boom_drive }

    MeetTranscriptService.new(analysis: analysis).call

    assert_empty analysis.updated_columns
  end
end
