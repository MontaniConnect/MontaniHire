require "open3"
require "tempfile"

class WhisperTranscriptionService
  MODEL_PATH  = Rails.root.join("vendor", "whisper_models", "ggml-small.en.bin").to_s
  WHISPER_CLI = "/opt/homebrew/bin/whisper-cli"

  def initialize(analysis:)
    @analysis = analysis
  end

  def call(video_tmp: nil)
    @analysis.transition_to!("transcribing")
    raise "Whisper model not found. Run: rails whisper:download_model" unless File.exist?(MODEL_PATH)

    caller_owns_tmp = video_tmp.present?
    video_tmp     ||= download_video
    wav_path        = extract_audio(video_tmp.path)
    transcript      = transcribe(wav_path)

    cleaned = TranscriptCleanerService.call(transcript)
    @analysis.update!(transcript: transcript, cleaned_transcript: cleaned)
    transcript
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
      "-otxt", "-of", out_base,
      "--no-prints"
    )
    raise "whisper-cli failed: #{stderr}" unless status.success?

    txt_path = "#{out_base}.txt"
    raise "Whisper output not found: #{txt_path}" unless File.exist?(txt_path)

    transcript = File.read(txt_path).strip
    File.unlink(txt_path)
    transcript
  end
end
