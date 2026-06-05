defmodule Gherkin.Dialect do
  @moduledoc """
  The i18n foundation: loads the vendored `priv/gherkin-languages.json` (80 dialects)
  and exposes the keyword set for any supported language code.

  This is pure, well-defined data and is implemented in full — it is the part the
  scanner/parser will lean on to classify lines in non-English features and to honour
  the `# language: xx` header.

  The JSON is parsed once at module load and cached in `:persistent_term`, so lookups
  are cheap and the 60 KB file isn't re-read per parse.

  ## Keyword groups

  Each dialect maps these groups to a list of literal keyword strings:

    * `:feature`, `:background`, `:rule`, `:scenario`, `:scenario_outline`, `:examples`
    * `:given`, `:when`, `:then`, `:and`, `:but` (step keywords)

  Step-keyword lists include the trailing space the reference output keeps (e.g.
  `"Given "`) and the `"* "` bullet alias. Block keywords (`Feature`, etc.) do not.

  ## Examples

      iex> Gherkin.Dialect.exists?("en")
      true

      iex> Gherkin.Dialect.exists?("no-such")
      false

      iex> {:ok, en} = Gherkin.Dialect.get("en")
      iex> en.name
      "English"

      iex> Gherkin.Dialect.keywords!("en", :given)
      ["* ", "Given "]

      iex> Gherkin.Dialect.keywords!("fr", :feature)
      ["Fonctionnalité"]
  """

  @persistent_term_key {__MODULE__, :dialects}

  @group_keys %{
    feature: "feature",
    background: "background",
    rule: "rule",
    scenario: "scenario",
    scenario_outline: "scenarioOutline",
    examples: "examples",
    given: "given",
    when: "when",
    then: "then",
    and: "and",
    but: "but"
  }

  @step_groups [:given, :when, :then, :and, :but]

  @type group ::
          :feature
          | :background
          | :rule
          | :scenario
          | :scenario_outline
          | :examples
          | :given
          | :when
          | :then
          | :and
          | :but

  @type t :: %{
          required(:language) => String.t(),
          required(:name) => String.t(),
          required(:native) => String.t(),
          required(group()) => [String.t()]
        }

  @doc "Absolute path to the vendored dialect data file."
  @spec languages_path() :: String.t()
  def languages_path do
    Path.join(:code.priv_dir(:gherkin), "gherkin-languages.json")
  end

  @doc "Returns the full map of `language_code => dialect`."
  @spec all() :: %{optional(String.t()) => t()}
  def all do
    case :persistent_term.get(@persistent_term_key, nil) do
      nil ->
        dialects = load!()
        :persistent_term.put(@persistent_term_key, dialects)
        dialects

      dialects ->
        dialects
    end
  end

  @doc "All supported language codes (e.g. `\"en\"`, `\"fr\"`, ...)."
  @spec language_codes() :: [String.t()]
  def language_codes, do: all() |> Map.keys() |> Enum.sort()

  @doc "How many dialects are loaded. Should be 80 for the vendored upstream data."
  @spec count() :: non_neg_integer()
  def count, do: map_size(all())

  @doc "Whether `language` is a supported dialect code."
  @spec exists?(String.t()) :: boolean()
  def exists?(language), do: Map.has_key?(all(), language)

  @doc """
  Fetch a dialect by language code.

  Returns `{:ok, dialect}` or `{:error, {:language_not_supported, language}}`. The
  error tuple matches the message the `bad/invalid_language.feature` golden expects
  (`"Language not supported: <code>"`).
  """
  @spec get(String.t()) :: {:ok, t()} | {:error, {:language_not_supported, String.t()}}
  def get(language) do
    case Map.fetch(all(), language) do
      {:ok, dialect} -> {:ok, dialect}
      :error -> {:error, {:language_not_supported, language}}
    end
  end

  @doc "Like `get/1` but raises `Gherkin.Dialect.UnknownLanguageError` on an unknown code."
  @spec get!(String.t()) :: t()
  def get!(language) do
    case get(language) do
      {:ok, dialect} ->
        dialect

      {:error, {:language_not_supported, lang}} ->
        raise __MODULE__.UnknownLanguageError, language: lang
    end
  end

  @doc "Keyword list for a `group` within `language`, or `{:error, ...}` if the language is unknown."
  @spec keywords(String.t(), group()) ::
          {:ok, [String.t()]} | {:error, {:language_not_supported, String.t()}}
  def keywords(language, group) when is_map_key(@group_keys, group) do
    with {:ok, dialect} <- get(language) do
      {:ok, Map.fetch!(dialect, group)}
    end
  end

  @doc "Like `keywords/2` but raises on an unknown language."
  @spec keywords!(String.t(), group()) :: [String.t()]
  def keywords!(language, group) when is_map_key(@group_keys, group) do
    get!(language) |> Map.fetch!(group)
  end

  @doc """
  All step keywords (`given|when|then|and|but`) for `language`, de-duplicated.
  Useful for the scanner when classifying a step line regardless of which step
  keyword it is.
  """
  @spec step_keywords!(String.t()) :: [String.t()]
  def step_keywords!(language) do
    dialect = get!(language)
    @step_groups |> Enum.flat_map(&Map.fetch!(dialect, &1)) |> Enum.uniq()
  end

  # --- internal -------------------------------------------------------------

  defp load! do
    languages_path()
    |> File.read!()
    |> Jason.decode!()
    |> Map.new(fn {code, raw} -> {code, normalize(code, raw)} end)
  end

  defp normalize(code, raw) do
    base = %{
      language: code,
      name: Map.get(raw, "name", code),
      native: Map.get(raw, "native", code)
    }

    Enum.reduce(@group_keys, base, fn {group, json_key}, acc ->
      Map.put(acc, group, Map.get(raw, json_key, []))
    end)
  end

  defmodule UnknownLanguageError do
    @moduledoc "Raised when a dialect is requested for an unsupported language code."
    defexception [:language]

    @impl true
    def message(%{language: language}), do: "Language not supported: #{language}"
  end
end
