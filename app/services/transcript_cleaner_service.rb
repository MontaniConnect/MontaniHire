class TranscriptCleanerService
  # Ordered longest-first so "you know what I mean" is caught before "you know"
  FILLER_PHRASES = [
    "you know what I mean",
    "you know",
    "I mean",
    "kind of",
    "sort of",
  ].freeze

  # Single-word fillers that are almost never meaningful
  FILLER_WORDS = %w[um uh hmm mm ah er erm].freeze

  def self.call(text)
    new(text: text).clean
  end

  def initialize(text:)
    @text = text.to_s.dup
  end

  def clean
    t = @text
    t = strip_filler_phrases(t)
    t = strip_filler_words(t)
    t = strip_stutters(t)
    t = collapse_repeated_words(t)
    t = fix_punctuation(t)
    t = normalize_whitespace(t)
    t
  end

  private

  def strip_filler_phrases(text)
    FILLER_PHRASES.each do |phrase|
      # Remove phrase and any immediately surrounding comma + space
      text = text.gsub(/,?\s*\b#{Regexp.escape(phrase)}\b\s*,?/i, " ")
    end
    text
  end

  def strip_filler_words(text)
    # Match the word, optional trailing comma, and surrounding whitespace
    text.gsub(/\b(#{FILLER_WORDS.join("|")})\b,?\s*/i, " ")
  end

  def strip_stutters(text)
    # Partial-word stutters: "I- I", "be-because", "s-sometimes"
    # Strip the incomplete fragment (1–4 chars + dash) before the real word
    text.gsub(/\b\w{1,4}-\s*/i, "")
  end

  def collapse_repeated_words(text)
    # "I I think" → "I think"; run twice to catch triplets
    2.times { text = text.gsub(/\b(\w+)\s+\1\b/i, '\1') }
    text
  end

  def fix_punctuation(text)
    text
      .gsub(/\s+([,\.!?;:])/, '\1')  # space before punctuation
      .gsub(/,\s*\./, ".")            # comma immediately before period
      .gsub(/,\s*,/, ",")             # double comma
      .gsub(/^[,\s]+/, "")           # leading junk at line start
  end

  def normalize_whitespace(text)
    text
      .gsub(/[ \t]{2,}/, " ")
      .gsub(/\n{3,}/, "\n\n")
      .strip
  end
end
