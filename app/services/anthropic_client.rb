require "anthropic"

class AnthropicClient
  def initialize
    @client = Anthropic::Client.new(api_key: ENV.fetch("ANTHROPIC_API_KEY"))
  end

  def complete(model:, system:, messages:, max_tokens: 4096, temperature: 0)
    response = @client.messages.create(
      model:      model,
      max_tokens: max_tokens,
      temperature: temperature,
      system:     system,
      messages:   messages
    )
    raw = response.content.first.text
              .gsub(/\A```(?:json)?\n?/, "")
              .gsub(/\n?```\z/, "")
              .strip
    JSON.parse(raw)
  rescue JSON::ParserError => e
    raise "Claude returned invalid JSON: #{e.message}"
  end
end
