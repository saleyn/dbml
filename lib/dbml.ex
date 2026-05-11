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

      {:ok, _, str, _, loc, pos} ->
        clause_end_pos = compute_error_clause_end(doc, pos)
        clause_end_loc = byte_offset_to_line_col(doc, clause_end_pos)

        {:error,
         %{
           input: str,
           location: loc,
           position: pos,
           clause_end_position: clause_end_pos,
           clause_end_location: clause_end_loc
         }}

      other ->
        {:error, other}
    end
  end

  defp compute_error_clause_end(doc, start_pos) do
    regex = ~r/^[ \t]*(?:table|ref|enum|project|TableGroup)\b/m

    case Regex.run(regex, doc, return: :index, offset: start_pos + 1) do
      [{idx, _length}] -> idx
      nil -> byte_size(doc)
    end
  end

  defp byte_offset_to_line_col(doc, pos) do
    prefix = :erlang.binary_part(doc, 0, pos)
    lines = :binary.split(prefix, "\n", [:global])
    line = length(lines)
    col = byte_size(List.last(lines)) + 1
    {line, col}
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

  @doc """
  Generate Ecto schema files from parsed DBML tokens.

  ## Options
    * `:namespace` - module namespace prefix (e.g. `"MyApp.Schema"`).
      Defaults to the project name from the DBML tokens, or `""` if absent.
    * `:singularize` - whether to singularize table names for module names (default: `true`).
      Set to `false` to use table names as-is (e.g., `users` → `Users` instead of `users` → `User`).
    * `:update` - if `false` (default), returns an error if any schema file already exists.
      If `true`, overwrites existing files with the newly-generated content.

  Returns `{:ok, paths}` on success, or `{:error, message}` if a file already exists (when update: false).
  """
  def generate_ecto_schemas(tokens, output_dir, opts \\ []) do
    namespace = Keyword.get(opts, :namespace, extract_project_name(tokens) || "")
    singularize = Keyword.get(opts, :singularize, true)
    update = Keyword.get(opts, :update, false)
    DBML.Ecto.Generator.generate(tokens, output_dir, namespace, singularize, update)
  end

  @doc """
  Generate Ecto migration files from parsed DBML tokens.

  ## Options
    * `:base_timestamp` - integer timestamp prefix for file names (default: 20000101000000).
      Each table gets `base + index`.
    * `:update` - if `false` (default), returns an error if any migration file already exists.
      If `true`, compares schema with existing migrations and creates new ones for changed tables.
    * `:overwrite` - if `true`, overwrites existing migration files without checking (default: false).

  Returns `{:ok, paths}` on success, or `{:error, message}` if a file already exists (when both update and overwrite are false).
  """
  def generate_ecto_migrations(tokens, output_dir, repo_module, opts \\ []) do
    DBML.Ecto.MigrationGenerator.generate(tokens, output_dir, repo_module, opts)
  end

  @doc """
  Generate a DBML schema file from existing Ecto schema files.

  Reads all `*.ex` files in `input_dir` that contain `use Ecto.Schema`,
  parses their structure, and writes a single `.dbml` file to `output_path`.

  ## Options
    * `:project_name` - name for the DBML project block (optional).
    * `:database_type` - database type string (default: `"PostgreSQL"`).

  Returns `{:ok, output_path}` or `{:error, reason}`.
  """
  def schemas_to_dbml(input_dir, output_path, opts \\ []) do
    with {:ok, tables} <- DBML.Ecto.SchemaReader.read_dir(input_dir) do
      DBML.Ecto.DBMLWriter.write(tables, output_path, opts)
    end
  end
  defp extract_project_name(tokens) do
    case Keyword.get(tokens, :project) do
      nil -> nil
      proj -> proj[:name]
    end
  end
end
