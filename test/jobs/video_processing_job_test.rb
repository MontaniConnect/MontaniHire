require "test_helper"

class VideoProcessingJobTest < ActiveSupport::TestCase
  # ── Test doubles ──────────────────────────────────────────────────────────

  # Stands in for an injected service class.
  # Responds to .new(analysis:) — returns self — and #call.
  class ServiceSpy
    attr_reader :called_with

    def initialize(return_value: nil)
      @return_value = return_value
      @called_with  = nil
    end

    def new(analysis:)
      @called_with = analysis
      self
    end

    def call = @return_value
    def called? = !@called_with.nil?
  end

  class FakeAnalysis
    attr_accessor :status, :transcript, :drive_file_id, :last_error
    attr_reader :id

    def initialize(id: 1, status: "pending", transcript: nil, drive_file_id: nil)
      @id            = id
      @status        = status
      @transcript    = transcript
      @drive_file_id = drive_file_id
    end

    def completed? = @status == "completed"
    def failed?    = @status == "failed"
    def reload     = self

    def transition_to!(new_status, error: nil)
      @status     = new_status
      @last_error = error
    end

    def update!(attrs)
      @transcript = attrs[:transcript] if attrs.key?(:transcript)
    end
  end

  class FakeCvAnalysis
    def initialize(completed:) = (@completed = completed)
    def completed? = @completed
  end

  FakeCandidate = Struct.new(:cv_analysis, keyword_init: true) do
    def video_analysis = nil
    def cv_ready? = cv_analysis&.completed?
  end

  NULL_SERVICE = ServiceSpy.new

  # ── Stub helpers ───────────────────────────────────────────────────────────
  # Temporarily define a singleton method on a class and restore via
  # remove_method so AR's inherited chain is unaffected afterward.

  def with_ar_stubs(analysis:, candidate:, &block)
    VideoAnalysis.define_singleton_method(:find)   { |*| analysis }
    Candidate.define_singleton_method(:find_by)    { |*_a, **_k| candidate }
    block.call
  ensure
    VideoAnalysis.singleton_class.remove_method(:find)  rescue nil
    Candidate.singleton_class.remove_method(:find_by)   rescue nil
  end

  def run_job(analysis, transcript_service: NULL_SERVICE, analysis_service: NULL_SERVICE, candidate: nil)
    with_ar_stubs(analysis: analysis, candidate: candidate) do
      VideoProcessingJob.new.perform(
        analysis.id,
        transcript_service: transcript_service,
        analysis_service:   analysis_service
      )
    end
  end

  # ── Guard: already terminal ────────────────────────────────────────────────

  test "returns immediately when analysis is already completed" do
    spy = ServiceSpy.new
    run_job(FakeAnalysis.new(status: "completed"), analysis_service: spy)
    assert_not spy.called?
  end

  test "returns immediately when analysis is already failed" do
    spy = ServiceSpy.new
    run_job(FakeAnalysis.new(status: "failed"), analysis_service: spy)
    assert_not spy.called?
  end

  # ── Drive transcription path ───────────────────────────────────────────────

  test "calls transcript_service when drive_file_id is present" do
    analysis       = FakeAnalysis.new(drive_file_id: "abc123")
    transcript_spy = ServiceSpy.new(return_value: "Hello world")

    run_job(analysis, transcript_service: transcript_spy)

    assert transcript_spy.called?
    assert_equal analysis, transcript_spy.called_with
  end

  test "stores transcript returned by transcript_service" do
    analysis       = FakeAnalysis.new(drive_file_id: "abc123")
    transcript_spy = ServiceSpy.new(return_value: "Hello world")

    run_job(analysis, transcript_service: transcript_spy)

    assert_equal "Hello world", analysis.transcript
  end

  test "transitions to failed when transcript_service returns blank" do
    analysis       = FakeAnalysis.new(drive_file_id: "abc123")
    transcript_spy = ServiceSpy.new(return_value: nil)

    run_job(analysis, transcript_service: transcript_spy)

    assert_equal "failed", analysis.status
    assert_match(/No Google Meet transcript found/, analysis.last_error)
  end

  # ── Awaiting-CV gate ───────────────────────────────────────────────────────

  test "transitions to awaiting_cv when candidate is nil" do
    analysis = FakeAnalysis.new(transcript: "Hello world")

    run_job(analysis, candidate: nil)

    assert_equal "awaiting_cv", analysis.status
  end

  test "transitions to awaiting_cv when candidate has no completed CV" do
    analysis  = FakeAnalysis.new(transcript: "Hello world")
    candidate = FakeCandidate.new(cv_analysis: FakeCvAnalysis.new(completed: false))

    run_job(analysis, candidate: candidate)

    assert_equal "awaiting_cv", analysis.status
  end

  test "calls analysis_service when transcript is present and CV is completed" do
    analysis      = FakeAnalysis.new(transcript: "Hello world")
    analysis_spy  = ServiceSpy.new
    candidate     = FakeCandidate.new(cv_analysis: FakeCvAnalysis.new(completed: true))

    run_job(analysis, analysis_service: analysis_spy, candidate: candidate)

    assert analysis_spy.called?
  end

  test "does not transition to awaiting_cv when CV is already completed" do
    analysis      = FakeAnalysis.new(transcript: "Hello world")
    analysis_spy  = ServiceSpy.new
    candidate     = FakeCandidate.new(cv_analysis: FakeCvAnalysis.new(completed: true))

    run_job(analysis, analysis_service: analysis_spy, candidate: candidate)

    assert_not_equal "awaiting_cv", analysis.status
  end

  # ── Rescue path ────────────────────────────────────────────────────────────

  test "transitions to failed and re-raises on unexpected error" do
    analysis = FakeAnalysis.new(drive_file_id: "abc123")
    boom     = ServiceSpy.new
    boom.define_singleton_method(:new) { |**_| raise "network timeout" }

    err = assert_raises(RuntimeError) { run_job(analysis, transcript_service: boom) }

    assert_match(/network timeout/, err.message)
    assert_equal "failed", analysis.status
    assert_equal "network timeout", analysis.last_error
  end
end
