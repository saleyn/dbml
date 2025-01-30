defmodule DBML do
  @doc """
  Parse a given string with a DBML schema definition

  ## Example:
      iex> DBML.parse("table a { c1 [pk] }")
      {:ok, [table: [name: "a", definitions: [column: [name: "c1", type: "[pk]"]]]]}
  """
  def parse(doc) do
    case DBML.Parser.parse(doc) do
      {:ok, tokens, "", _, _, _} ->
        {:ok, tokens}

      other ->
        {:error, other}
    end
  end

  @doc """
  Parse a file containing a DBML schema definition
  """
  def parse_file(file) do
    with {:ok, doc} <- File.read(file),
         {:ok, tokens} <- parse(doc) do
      {:ok, tokens}
    else
      error ->
        error
    end
  end
end
