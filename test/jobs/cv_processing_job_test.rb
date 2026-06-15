require "test_helper"

class CvProcessingJobTest < ActiveSupport::TestCase
  # ── Test doubles ──────────────────────────────────────────────────────────

  class ServiceSpy
    attr_reader :called_with

    def initialize = (@called_with = nil)

    def new(analysis:)
      @called_with = analysis
      self
    end

    def call = nil
    def called? = !@called_with.nil?
  end

  class FakeAnalysis
    attr_accessor :status, :extracted_text, :last_error
    attr_reader :id

    def initialize(id: 1, status: "pending", extracted_text: nil, candidate: nil)
      @id             = id
      @status         = status
      @extracted_text = extracted_text
      @candidate      = candidate
    end

    def completed? = @status == "completed"
    def failed?    = @status == "failed"

    def candidate = @candidate

    def transition_to!(new_status, error: nil)
      @status     = new_status
      @last_error = error
    end
  end

  class FakeVideoAnalysis
    attr_reader :id, :awaiting_cv_called
    def initialize(id: 99, awaiting_cv: false)
      @id              = id
      @_awaiting_cv    = awaiting_cv
      @awaiting_cv_called = false
    end
    def awaiting_cv? = @_awaiting_cv
  end

  class FakeCandidate
    attr_accessor :email, :video_analysis
    attr_reader :email_updated_to

    def initialize(email: nil, video_analysis: nil)
      @email          = email
      @video_analysis = video_analysis
    end

    def blank? = email.nil? || email.empty?

    def update_columns(attrs)
      @email_updated_to = attrs[:email] if attrs.key?(:email)
      @email            = attrs[:email] if attrs.key?(:email)
    end
  end

  NULL_SERVICE = ServiceSpy.new

  # ── Stub helpers ───────────────────────────────────────────────────────────

  def with_cv_stubs(analysis:, &block)
    CvAnalysis.define_singleton_method(:find) { |*| analysis }
    block.call
  ensure
    CvAnalysis.singleton_class.remove_method(:find) rescue nil
  end

  def run_job(analysis, extraction_service: NULL_SERVICE, analysis_service: NULL_SERVICE)
    with_cv_stubs(analysis: analysis) do
      CvProcessingJob.new.perform(
        analysis.id,
        extraction_service: extraction_service,
        analysis_service:   analysis_service
      )
    end
  end

  # ── Guard: already terminal ────────────────────────────────────────────────

  test "returns immediately when analysis is already completed" do
    extraction_spy = ServiceSpy.new
    run_job(FakeAnalysis.new(status: "completed"), extraction_service: extraction_spy)
    assert_not extraction_spy.called?
  end

  test "returns immediately when analysis is already failed" do
    extraction_spy = ServiceSpy.new
    run_job(FakeAnalysis.new(status: "failed"), extraction_service: extraction_spy)
    assert_not extraction_spy.called?
  end

  # ── Service call order ─────────────────────────────────────────────────────

  test "calls extraction_service then analysis_service" do
    extraction_spy = ServiceSpy.new
    analysis_spy   = ServiceSpy.new

    run_job(FakeAnalysis.new, extraction_service: extraction_spy, analysis_service: analysis_spy)

    assert extraction_spy.called?, "extraction_service should be called"
    assert analysis_spy.called?,   "analysis_service should be called"
  end

  test "passes the analysis record to both services" do
    analysis       = FakeAnalysis.new
    extraction_spy = ServiceSpy.new
    analysis_spy   = ServiceSpy.new

    run_job(analysis, extraction_service: extraction_spy, analysis_service: analysis_spy)

    assert_equal analysis, extraction_spy.called_with
    assert_equal analysis, analysis_spy.called_with
  end

  # ── Email extraction ───────────────────────────────────────────────────────

  test "extracts and saves email from extracted_text when candidate has none" do
    candidate = FakeCandidate.new(email: "")
    # Email must appear without a short alphanumeric word on the next line —
    # the collapse regex grabs up to 6 chars after any newline following an
    # email pattern, which would corrupt the address.
    analysis  = FakeAnalysis.new(
      extracted_text: "Applicant: John Smith\nContact: john.smith@example.com",
      candidate: candidate
    )

    run_job(analysis)

    assert_equal "john.smith@example.com", candidate.email_updated_to
  end

  test "collapses split email across newlines before matching" do
    candidate = FakeCandidate.new(email: "")
    analysis  = FakeAnalysis.new(
      extracted_text: "Contact: jsmith@example\n.com for details",
      candidate: candidate
    )

    run_job(analysis)

    assert_equal "jsmith@example.com", candidate.email_updated_to
  end

  test "does not overwrite email when candidate already has one" do
    candidate = FakeCandidate.new(email: "existing@example.com")
    analysis  = FakeAnalysis.new(
      extracted_text: "fallback@example.com",
      candidate: candidate
    )

    run_job(analysis)

    assert_nil candidate.email_updated_to
  end

  test "does not update email when extracted_text has no address" do
    candidate = FakeCandidate.new(email: "")
    analysis  = FakeAnalysis.new(extracted_text: "No contact info here.", candidate: candidate)

    run_job(analysis)

    assert_nil candidate.email_updated_to
  end

  test "skips email extraction when candidate is nil" do
    analysis = FakeAnalysis.new(extracted_text: "someone@example.com", candidate: nil)
    assert_nothing_raised { run_job(analysis) }
  end

  # ── VideoProcessingJob kick-off ────────────────────────────────────────────

  test "enqueues VideoProcessingJob when video_analysis is awaiting_cv" do
    video_analysis = FakeVideoAnalysis.new(id: 99, awaiting_cv: true)
    candidate      = FakeCandidate.new(email: "x@example.com",
                                       video_analysis: video_analysis)
    analysis       = FakeAnalysis.new(candidate: candidate)

    enqueued = []
    VideoProcessingJob.define_singleton_method(:perform_later) { |id| enqueued << id }
    run_job(analysis)
    assert_includes enqueued, 99
  ensure
    VideoProcessingJob.singleton_class.remove_method(:perform_later) rescue nil
  end

  test "does not enqueue VideoProcessingJob when video_analysis is not awaiting_cv" do
    video_analysis = FakeVideoAnalysis.new(awaiting_cv: false)
    candidate      = FakeCandidate.new(email: "x@example.com",
                                       video_analysis: video_analysis)
    analysis       = FakeAnalysis.new(candidate: candidate)

    enqueued = []
    VideoProcessingJob.define_singleton_method(:perform_later) { |id| enqueued << id }
    run_job(analysis)
    assert_empty enqueued
  ensure
    VideoProcessingJob.singleton_class.remove_method(:perform_later) rescue nil
  end

  # ── Rescue path ────────────────────────────────────────────────────────────

  test "transitions to failed and re-raises on error" do
    analysis = FakeAnalysis.new
    boom     = ServiceSpy.new
    boom.define_singleton_method(:new) { |**_| raise "disk full" }

    err = assert_raises(RuntimeError) { run_job(analysis, extraction_service: boom) }

    assert_match(/disk full/, err.message)
    assert_equal "failed", analysis.status
    assert_equal "disk full", analysis.last_error
  end
end
