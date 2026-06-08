require "anthropic"

class JobRoleRequirementsService
  MODEL = "claude-haiku-4-5-20251001"

  SYSTEM_PROMPT = <<~PROMPT
    You are a job description analyst. Extract and classify requirements from a job description into two lists.

    Must-have requirements: skills, tools, qualifications, or experience the candidate MUST have to be considered. Absence alone is a strong negative signal.

    Nice-to-have requirements: preferred or bonus skills that strengthen a candidacy but whose absence does not disqualify.

    Rules:
    - Each requirement must be specific — name the actual tool, technology, or competency (not a generic category)
    - Keep each item concise: 5–15 words
    - Do not duplicate items across lists
    - Do not include generic soft skills ("team player", "fast learner") — only assessable, role-specific requirements
    - Must-have count should be between 6 and 12
    - Nice-to-have count should be between 2 and 8

    Return a JSON object with exactly two keys:
    {
      "must_have": ["...", "..."],
      "nice_to_have": ["...", "..."]
    }

    Return only valid JSON. No markdown, no explanation.
  PROMPT

  def initialize(job_role)
    @job_role = job_role
    @client   = Anthropic::Client.new(api_key: ENV.fetch("ANTHROPIC_API_KEY"))
  end

  def call
    response = @client.messages.create(
      model:      MODEL,
      max_tokens: 1024,
      system:     SYSTEM_PROMPT,
      messages:   [{ role: "user", content: build_prompt }]
    )

    raw = response.content.first.text.gsub(/\A```(?:json)?\n?/, "").gsub(/\n?```\z/, "").strip
    result = JSON.parse(raw)

    {
      must_have:    Array(result["must_have"]).map(&:strip).reject(&:blank?),
      nice_to_have: Array(result["nice_to_have"]).map(&:strip).reject(&:blank?)
    }
  rescue JSON::ParserError => e
    raise "Failed to parse requirements: #{e.message}"
  end

  private

  def build_prompt
    parts = ["Job Title: #{@job_role.title}", "Experience Level: #{@job_role.experience_level.capitalize}"]
    parts << "Required Skills:\n#{@job_role.required_skills.to_plain_text}" if @job_role.required_skills.present?
    parts << "Responsibilities:\n#{@job_role.responsibilities.to_plain_text}" if @job_role.responsibilities.present?
    parts << "Additional Context:\n#{@job_role.description}" if @job_role.description.present?
    parts.join("\n\n")
  end
end
