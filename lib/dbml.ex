defmodule DBML do
  @doc """
  Parse a given string with a DBML schema definition

  ## Example:
      iex> DBML.parse("table a { c1 [pk] }")
      {:ok, [table: %{name: "a", fields: [%{name: "c1", type: "[pk]"}]}]}
  """
  def parse(doc, options \\ []) do
    case DBML.Parser.parse(doc, options) do
      {:ok, tokens, "", _, _, _} ->
        {:ok, tokens}

      other ->
        {:error, other}
    end
  end

  @doc """
  Parse a file containing a DBML schema definition.

  ## Options

    * `:inline` - when true, inlines clauses that work as redirection for
      other clauses. Settings this may improve runtime performance at the
      cost of increased compilation time and bytecode size

    * `:debug` - when true, writes generated clauses to `:stderr` for debugging

    * `:export_combinator` - make the underlying combinator function public
      so it can be used as part of `parsec/1` from other modules

    * `:export_metadata` - export metadata necessary to use this parser
      combinator to generate inputs
  """
  def parse_file(file, options \\ []) do
    with {:ok, doc} <- File.read(file),
         {:ok, tokens} <- parse(doc, options) do
      {:ok, tokens}
    else
      error ->
        error
    end
  end
end
