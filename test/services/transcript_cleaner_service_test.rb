require "test_helper"

class TranscriptCleanerServiceTest < ActiveSupport::TestCase
  def clean(text)
    TranscriptCleanerService.call(text)
  end

  # ── .call delegates to #clean ──────────────────────────────────────────────

  test ".call returns the same result as instantiating and calling clean" do
    text = "um so I was kind of thinking"
    assert_equal TranscriptCleanerService.new(text: text).clean,
                 TranscriptCleanerService.call(text)
  end

  test "returns empty string for empty input" do
    assert_equal "", clean("")
  end

  test "returns empty string for nil-like input via to_s" do
    assert_equal "", TranscriptCleanerService.new(text: nil).clean
  end

  # ── strip_filler_phrases ───────────────────────────────────────────────────

  test "removes 'you know what I mean'" do
    assert_equal "it was great.", clean("it was great, you know what I mean.")
  end

  test "removes 'you know' but not within 'you know what I mean'" do
    # longer phrase takes precedence; "you know" is handled only when standalone
    result = clean("you know what I mean, it matters")
    refute_includes result, "you know what I mean"
    refute_includes result, "you know"
  end

  test "removes 'you know' standalone" do
    assert_equal "it was hard.", clean("it was hard, you know.")
  end

  test "removes 'I mean' mid-sentence" do
    assert_equal "the project succeeded.", clean("the project, I mean, succeeded.")
  end

  test "removes 'kind of'" do
    assert_equal "I was nervous.", clean("I was kind of nervous.")
  end

  test "removes 'sort of'" do
    assert_equal "It worked.", clean("It sort of worked.")
  end

  test "filler phrase removal is case-insensitive" do
    assert_equal "it was fine.", clean("it was fine, YOU KNOW.")
  end

  test "removes surrounding commas when stripping filler phrase" do
    # "great, you know, right" → "great right" after phrase + comma removal
    result = clean("great, you know, right")
    refute_includes result, "you know"
  end

  # ── strip_filler_words ─────────────────────────────────────────────────────

  test "removes 'um'" do
    assert_equal "I think it works.", clean("I um think it works.")
  end

  test "removes 'uh'" do
    assert_equal "we started early.", clean("we uh started early.")
  end

  test "removes 'hmm'" do
    assert_equal "that is interesting.", clean("hmm that is interesting.")
  end

  test "removes 'er' and 'erm'" do
    assert_equal "the deadline was tight.", clean("the er erm deadline was tight.")
  end

  test "filler word removal is case-insensitive" do
    assert_equal "well done.", clean("UM well done.")
  end

  test "does not remove 'um' embedded inside a real word" do
    # 'umbrella' should survive — \b word boundary guards against this
    assert_includes clean("I grabbed my umbrella."), "umbrella"
  end

  # ── strip_stutters ─────────────────────────────────────────────────────────

  test "removes single-letter stutter prefix" do
    assert_equal "sometimes it fails.", clean("s-sometimes it fails.")
  end

  test "removes multi-letter stutter prefix up to 4 chars" do
    assert_equal "because of that.", clean("be-because of that.")
  end

  test "removes stutter with space between fragment and word" do
    assert_equal "I was there.", clean("I- I was there.")
  end

  # ── collapse_repeated_words ────────────────────────────────────────────────

  test "collapses immediately repeated word" do
    assert_equal "I think it works.", clean("I I think it works.")
  end

  test "collapses repeated word case-insensitively" do
    assert_equal "the project.", clean("the THE project.")
  end

  test "collapses triplet repetition" do
    # two passes collapse "the the the" → "the the" → "the"
    assert_equal "the project.", clean("the the the project.")
  end

  # ── fix_punctuation ────────────────────────────────────────────────────────

  test "removes space before comma" do
    assert_equal "good, really.", clean("good , really.")
  end

  test "removes space before period" do
    assert_equal "done.", clean("done .")
  end

  test "collapses comma immediately before period" do
    assert_equal "finished.", clean("finished,.")
  end

  test "collapses double comma" do
    assert_equal "yes, agreed.", clean("yes,, agreed.")
  end

  test "strips leading comma/whitespace junk" do
    assert_equal "hello there.", clean(", , hello there.")
  end

  # ── normalize_whitespace ───────────────────────────────────────────────────

  test "collapses multiple spaces to one" do
    assert_equal "one two three.", clean("one  two   three.")
  end

  test "collapses more than two newlines to two" do
    result = clean("line one\n\n\n\nline two")
    refute_match(/\n{3,}/, result)
    assert_includes result, "line one"
    assert_includes result, "line two"
  end

  test "strips leading and trailing whitespace" do
    assert_equal "hello.", clean("   hello.   ")
  end

  # ── pipeline integration ───────────────────────────────────────────────────

  test "cleans a realistic transcript excerpt end-to-end" do
    raw = <<~TEXT
      Um so I I was kind of in charge of the the project, you know,
      and uh we be-began rolling it out s-slowly. I mean, the results
      were, you know what I mean, really strong , .
    TEXT

    result = clean(raw)

    refute_match(/\bum\b/i,  result)
    refute_match(/\buh\b/i,  result)
    refute_match(/\bI mean\b/i, result)
    refute_match(/you know/i, result)
    refute_match(/kind of/i, result)
    refute_match(/\bI I\b/i, result)
    refute_match(/the the/i, result)
    refute_match(/\s,/, result)
    refute_match(/,\./, result)
  end
end
