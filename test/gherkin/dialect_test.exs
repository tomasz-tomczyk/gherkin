defmodule Gherkin.DialectTest do
  @moduledoc """
  Tests for the i18n foundation. The dialect data is pure, vendored, well-defined data,
  so this is the one piece of the new pipeline that is fully implemented and verifiable
  today — unlike the parser/pickles seams, which are still `:not_implemented`.
  """

  use ExUnit.Case, async: true

  alias Gherkin.Dialect

  doctest Dialect

  describe "the vendored language corpus" do
    test "loads all 80 upstream dialects" do
      assert Dialect.count() == 80
      assert map_size(Dialect.all()) == 80
    end

    test "language_codes/0 returns sorted, unique codes including the common ones" do
      codes = Dialect.language_codes()

      assert codes == Enum.sort(codes)
      assert codes == Enum.uniq(codes)
      assert length(codes) == 80

      for code <- ~w(en fr de es it pt ja zh-CN zh-TW ru) do
        assert code in codes, "expected #{code} in the dialect corpus"
      end
    end

    test "exists?/1 distinguishes known from unknown codes" do
      assert Dialect.exists?("en")
      assert Dialect.exists?("zh-TW")
      refute Dialect.exists?("no-such-language")
      refute Dialect.exists?("")
    end
  end

  describe "block keyword lookups" do
    test "English feature keywords" do
      assert Dialect.keywords!("en", :feature) == ["Feature", "Business Need", "Ability"]
    end

    test "French feature keyword" do
      assert Dialect.keywords!("fr", :feature) == ["Fonctionnalité"]
    end

    test "German feature keywords" do
      assert Dialect.keywords!("de", :feature) == ["Funktionalität", "Funktion"]
    end

    test "every dialect supplies at least one feature keyword" do
      for code <- Dialect.language_codes() do
        assert Dialect.keywords!(code, :feature) != [],
               "#{code} has no feature keyword"
      end
    end
  end

  describe "step keyword lookups" do
    test "English step keywords keep their trailing space and bullet alias" do
      assert Dialect.keywords!("en", :given) == ["* ", "Given "]
      assert Dialect.keywords!("en", :when) == ["* ", "When "]
      assert Dialect.keywords!("en", :then) == ["* ", "Then "]
    end

    test "step_keywords!/1 unions and de-duplicates all step groups" do
      en = Dialect.step_keywords!("en")

      # de-duplicated: the shared "* " bullet appears once, not five times.
      assert en == Enum.uniq(en)
      assert "* " in en
      assert "Given " in en
      assert "When " in en
      assert "Then " in en
      assert "And " in en
      assert "But " in en
    end
  end

  describe "error handling for unknown languages" do
    test "get/1 returns a tagged error tuple" do
      assert Dialect.get("nope") == {:error, {:language_not_supported, "nope"}}
    end

    test "get!/1 raises with the message the bad/invalid_language golden expects" do
      assert_raise Dialect.UnknownLanguageError, "Language not supported: nope", fn ->
        Dialect.get!("nope")
      end
    end

    test "keywords/2 propagates the unknown-language error" do
      assert Dialect.keywords("nope", :feature) ==
               {:error, {:language_not_supported, "nope"}}
    end

    test "keywords!/2 raises a FunctionClauseError for an unknown keyword group" do
      assert_raise FunctionClauseError, fn ->
        Dialect.keywords!("en", :not_a_group)
      end
    end
  end

  describe "dialect shape" do
    test "get!/1 returns name and native metadata" do
      en = Dialect.get!("en")
      assert en.name == "English"
      assert en.native == "English"
      assert en.language == "en"
    end
  end
end
