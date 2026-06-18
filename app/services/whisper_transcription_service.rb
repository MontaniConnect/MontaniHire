require "open3"
require "tempfile"

class WhisperTranscriptionService
  MODEL_PATH  = Rails.root.join("vendor", "whisper_models", "ggml-small.en.bin").to_s
  WHISPER_CLI = ENV.fetch("WHISPER_CLI_PATH", "/usr/local/bin/whisper-cli")

  def initialize(analysis:)
    @analysis = analysis
  end

  def call(video_tmp: nil)
    @analysis.transition_to!("transcribing")
    raise "Whisper model not found. Run: rails whisper:download_model" unless File.exist?(MODEL_PATH)

    caller_owns_tmp = video_tmp.present?
    video_tmp     ||= download_video
    wav_path        = extract_audio(video_tmp.path)
    result          = transcribe(wav_path)

    cleaned = TranscriptCleanerService.call(result[:text])
    @analysis.update!(
      transcript:          result[:text],
      transcript_segments: result[:segments],
      cleaned_transcript:  cleaned
    )
    result[:text]
  ensure
    unless caller_owns_tmp
      video_tmp&.close
      video_tmp&.unlink
    end
    File.unlink(wav_path) if wav_path && File.exist?(wav_path)
  end

  private

  def download_video
    tmp = Tempfile.new(["video", File.extname(@analysis.video.filename.to_s)], binmode: true)
    @analysis.video.download { |chunk| tmp.write(chunk) }
    tmp.rewind
    tmp
  end

  def extract_audio(video_path)
    wav_path = video_path.sub(/\.[^.]+$/, "_whisper.wav")
    _, stderr, status = Open3.capture3(
      "ffmpeg", "-i", video_path,
      "-ar", "16000", "-ac", "1", "-c:a", "pcm_s16le", "-y", wav_path
    )
    raise "ffmpeg failed: #{stderr}" unless status.success?
    wav_path
  end

  def transcribe(wav_path)
    out_base = wav_path.sub(/\.wav$/, "")
    _, stderr, status = Open3.capture3(
      WHISPER_CLI,
      "-m", MODEL_PATH,
      "-f", wav_path,
      "-ovtt", "-of", out_base,
      "--no-prints"
    )
    raise "whisper-cli failed: #{stderr}" unless status.success?

    vtt_path = "#{out_base}.vtt"
    raise "Whisper output not found: #{vtt_path}" unless File.exist?(vtt_path)

    raw    = File.read(vtt_path)
    parser = TranscriptParsers::Vtt.new
    File.unlink(vtt_path)
    { text: parser.parse(raw), segments: parser.parse_segments(raw) }
  end
end
