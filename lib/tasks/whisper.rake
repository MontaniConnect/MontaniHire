namespace :whisper do
  MODELS = {
    "small.en"        => { size: "148MB",  recommended: false },
    "medium.en"       => { size: "466MB",  recommended: false },
    "large-v3-turbo"  => { size: "806MB",  recommended: true  }
  }.freeze

  BASE_URL = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main"
  MODEL_DIR = Rails.root.join("vendor", "whisper_models")

  desc "Download a Whisper model (default: small.en). Use MODEL=large-v3-turbo for best accuracy."
  task download_model: :environment do
    model = ENV.fetch("MODEL", "small.en")
    info  = MODELS[model] or abort "Unknown model '#{model}'. Available: #{MODELS.keys.join(', ')}"

    dest = MODEL_DIR.join("ggml-#{model}.bin")
    if dest.exist?
      puts "Model already exists at #{dest}"
      next
    end

    url = "#{BASE_URL}/ggml-#{model}.bin"
    puts "Downloading #{model} (#{info[:size]}) from #{url}..."
    system("curl", "-L", "--progress-bar", url, "-o", dest.to_s) or abort "Download failed"
    puts "Saved to #{dest}"
  end

  desc "List available Whisper models and download status"
  task models: :environment do
    puts "\nWhisper models (stored in vendor/whisper_models/):\n\n"
    MODELS.each do |name, info|
      path      = MODEL_DIR.join("ggml-#{name}.bin")
      status    = path.exist? ? "✅ downloaded" : "   not downloaded"
      rec       = info[:recommended] ? " ← recommended" : ""
      puts "  #{status}  #{name} (#{info[:size]})#{rec}"
    end
    puts
  end
end
