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
    Rails.logger.info "[AnthropicClient] usage: input=#{response.usage.input_tokens} output=#{response.usage.output_tokens} cache_read=#{response.usage.cache_read_input_tokens.to_i} cache_write=#{response.usage.cache_creation_input_tokens.to_i}"
    raw = response.content.first.text
              .gsub(/\A```(?:json)?\n?/, "")
              .gsub(/\n?```\z/, "")
              .strip
    JSON.parse(raw)
  rescue JSON::ParserError => e
    Rails.logger.error "[AnthropicClient] JSON parse error. Raw response (first 300 chars): #{raw.first(300)}"
    raise "Claude returned invalid JSON: #{e.message}"
  end
end
