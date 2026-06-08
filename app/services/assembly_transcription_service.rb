require "assemblyai"

class AssemblyTranscriptionService
  POLL_INTERVAL = 5   # seconds
  POLL_TIMEOUT  = 600 # 10 minutes

  def initialize(analysis)
    @analysis = analysis
    @client = AssemblyAI::Client.new(api_key: ENV.fetch("ASSEMBLYAI_API_KEY"))
  end

  def call
    @analysis.transition_to!("transcribing")

    video_file = download_temp_file
    upload_url = @client.files.upload(file: video_file)

    transcript = @client.transcripts.transcribe(
      audio_url: upload_url,
      speaker_labels: true,
      language_detection: true
    )

    @analysis.update!(assembly_transcript_id: transcript.id)

    completed = poll_until_complete(transcript.id)
    @analysis.update!(transcript: completed.text)

    completed.text
  ensure
    video_file&.close
    video_file&.unlink
  end

  private

  def download_temp_file
    service = DriveDownloadService.new(@analysis)
    service.call
    service.temp_file
  end

  def poll_until_complete(transcript_id)
    deadline = Time.current + POLL_TIMEOUT

    loop do
      transcript = @client.transcripts.get(transcript_id: transcript_id)

      case transcript.status
      when "completed"
        return transcript
      when "error"
        raise "AssemblyAI transcription failed: #{transcript.error}"
      end

      raise "Transcription timed out after #{POLL_TIMEOUT}s" if Time.current > deadline

      sleep POLL_INTERVAL
    end
  end
end
