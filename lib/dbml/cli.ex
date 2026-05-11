defmodule DBML.CLI do
  @moduledoc """
  CLI entry point for DBML. Provides both escript (main/1) and programmatic
  (run/1) interfaces.
  """

  @schemas_switches [
    output_dir:  :string,
    namespace:   :string,
    update:      :boolean,
    overwrite:   :boolean,
    singularize: :boolean,
    help:        :boolean
  ]

  @schemas_aliases [
    o: :output_dir,
    n: :namespace,
    h: :help
  ]

  @migrations_switches [
    output_dir:     :string,
    repo:           :string,
    base_timestamp: :integer,
    update:         :boolean,
    overwrite:      :boolean,
    help:           :boolean
  ]

  @migrations_aliases [
    o: :output_dir,
    r: :repo,
    h: :help
  ]

  @file_switches [
    output:        :string,
    project_name:  :string,
    database_type: :string,
    help:          :boolean
  ]

  @file_aliases [
    o: :output,
    h: :help
  ]

  def main(argv) do
    case run(argv) do
      :ok ->
        :ok

      {:error, msg} ->
        IO.puts(:stderr, "Error: #{msg}")
        System.halt(1)
    end
  end

  def run([]), do: print_help()

  def run(["schemas"    | rest]), do: run_schemas(rest)
  def run(["migrations" | rest]), do: run_migrations(rest)
  def run(["file"       | rest]), do: run_file(rest)
  def run([help         | _]) when help in ["help", "--help", "-h"], do: print_help()
  def run([unknown      | _]) do
    {:error, "Unknown command: #{unknown}. Run 'dbml help' for usage."}
  end

  defp run_schemas(args) do
    {opts, positional, _invalid} =
      OptionParser.parse(args, switches: @schemas_switches, aliases: @schemas_aliases)

    if opts[:help] do
      print_schemas_help()
      :ok
    else
      case positional do
        [dbml_file] ->
          run_schemas_impl(dbml_file, opts)

        [] ->
          {:error, "schemas requires a DBML file argument"}

        _ ->
          {:error, "schemas takes exactly one DBML file argument"}
      end
    end
  end

  defp run_schemas_impl(dbml_file, opts) do
    with {:file_exists, true} <- {:file_exists, File.exists?(dbml_file)},
         {:ok, tokens} <- DBML.parse_file(dbml_file),
         {:output_dir, dir} when not is_nil(dir) <- {:output_dir, opts[:output_dir]},
         gen_opts <- build_schemas_opts(opts),
         {:ok, paths} <- DBML.generate_ecto_schemas(tokens, dir, gen_opts)
    do
      Enum.each(paths, &IO.puts("Generated: #{&1}"))
    else
      {:file_exists, false} ->
        {:error, "DBML file not found: #{dbml_file}"}

      {:output_dir, nil} ->
        {:error, "schemas requires --output-dir (-o) option"}

      {:error, reason} ->
        {:error, format_error(reason, dbml_file)}
    end
  end

  defp run_migrations(args) do
    {opts, positional, _invalid} = OptionParser.parse(args, switches: @migrations_switches, aliases: @migrations_aliases)

    if opts[:help] do
      print_migrations_help()
    else
      case positional do
        [dbml_file] ->
          run_migrations_impl(dbml_file, opts)

        [] ->
          {:error, "migrations requires a DBML file argument"}

        _ ->
          {:error, "migrations takes exactly one DBML file argument"}
      end
    end
  end

  defp run_migrations_impl(dbml_file, opts) do
    with {:file_exists, true} <- {:file_exists, File.exists?(dbml_file)},
         {:ok, tokens} <- DBML.parse_file(dbml_file),
         {:output_dir, dir} when not is_nil(dir) <- {:output_dir, opts[:output_dir]},
         {:repo, repo} when not is_nil(repo) <- {:repo, opts[:repo]},
         gen_opts <- build_migrations_opts(opts),
         {:ok, paths} <- DBML.generate_ecto_migrations(tokens, dir, repo, gen_opts)
    do
      Enum.each(paths, &IO.puts("Generated: #{&1}"))
    else
      {:file_exists, false} ->
        {:error, "DBML file not found: #{dbml_file}"}

      {:output_dir, nil} ->
        {:error, "migrations requires --output-dir (-o) option"}

      {:repo, nil} ->
        {:error, "migrations requires --repo (-r) option"}

      {:error, reason} ->
        {:error, format_error(reason, dbml_file)}
    end
  end

  defp run_file(args) do
    {opts, positional, _invalid} = OptionParser.parse(args, switches: @file_switches, aliases: @file_aliases)

    if opts[:help] do
      print_file_help()
    else
      case positional do
        [schemas_dir] ->
          run_file_impl(schemas_dir, opts)

        [] ->
          {:error, "file requires a schemas directory argument"}

        _ ->
          {:error, "file takes exactly one schemas directory argument"}
      end
    end
  end

  defp run_file_impl(schemas_dir, opts) do
    with {:dir_exists, true} <- {:dir_exists, File.exists?(schemas_dir)},
         {:output, output} when not is_nil(output) <- {:output, opts[:output]},
         gen_opts <- build_file_opts(opts),
         {:ok, _output_path} <- DBML.schemas_to_dbml(schemas_dir, output, gen_opts) do
      IO.puts("Generated: #{output}")
    else
      {:dir_exists, false} ->
        {:error, "Schemas directory not found: #{schemas_dir}"}

      {:output, nil} ->
        {:error, "file requires --output (-o) option"}

      {:error, reason} ->
        {:error, format_error(reason, schemas_dir)}
    end
  end

  defp build_schemas_opts(opts) do
    []
    |> add_opt(opts, :namespace, :namespace)
    |> add_opt(opts, :singularize, :singularize)
    |> add_opt(opts, :update, :update)
    |> add_opt(opts, :overwrite, :update)
  end

  defp build_migrations_opts(opts) do
    []
    |> add_opt(opts, :base_timestamp, :base_timestamp)
    |> add_opt(opts, :update, :update)
    |> add_opt(opts, :overwrite, :overwrite)
  end

  defp build_file_opts(opts) do
    []
    |> add_opt(opts, :project_name, :project_name)
    |> add_opt(opts, :database_type, :database_type)
  end

  defp add_opt(acc, opts, key, outkey) do
    case opts[key] do
      nil -> acc
      val -> [{outkey, val} | acc]
    end
  end

  defp format_error(%{input: _, location: {_line, _col}, position: position} = err, file_path) do
    case File.read(file_path) do
      {:ok, content} ->
        {line, col} = byte_offset_to_line_col(content, position)
        {clause_start_pos, clause_start_line} = find_clause_start(content, position)
        clause_end_pos = Map.get(err, :clause_end_position, byte_size(content))
        clause_text = extract_clause(content, clause_start_pos, clause_end_pos)
        clause_lines = String.split(clause_text, "\n", trim: false)

        pointer = String.duplicate(" ", col) <> "^^^"

        clause_display =
          clause_lines
          |> Enum.with_index(clause_start_line)
          |> Enum.flat_map(fn {clause_line, idx} ->
            if idx == line do
              ["  #{clause_line}", "  #{pointer}"]
            else
              ["  #{clause_line}"]
            end
          end)
          |> Enum.join("\n")

        """
        Parse error at line #{line}:

        #{clause_display}
        """

      {:error, _} ->
        "Parse error: #{err.input}"
    end
  end

  defp format_error(reason, _file_path) when is_binary(reason) do
    reason
  end

  defp format_error(reason, _file_path) do
    inspect(reason)
  end

  defp find_clause_start(content, position) do
    prefix = :erlang.binary_part(content, 0, position)
    regex = ~r/^[ \t]*(?:table|ref|enum|project|TableGroup)\b/m

    case Regex.scan(regex, prefix, return: :index) do
      [] ->
        line = length(String.split(prefix, "\n", trim: false))
        {find_line_start(content, position), line}

      matches ->
        {start_pos, _length} = List.last(matches)
        {start_pos, elem(byte_offset_to_line_col(content, start_pos), 0)}
    end
  end

  defp extract_clause(content, start_pos, end_pos) do
    length = max(0, end_pos - start_pos)
    content
    |> :erlang.binary_part(start_pos, length)
    |> to_string()
  end

  defp find_line_start(content, position) do
    prefix = :erlang.binary_part(content, 0, position)
    case :binary.matches(prefix, "\n") do
      [] -> 0
      matches ->
        {last_pos, _len} = List.last(matches)
        last_pos + 1
    end
  end

  defp byte_offset_to_line_col(doc, pos) do
    prefix = :erlang.binary_part(doc, 0, pos)
    lines = String.split(prefix, "\n", trim: false)
    line = length(lines)
    col = String.length(List.last(lines))
    {line, col}
  end

  defp print_help do
    IO.puts("""
    DBML — Database Markup Language tools

    USAGE:
        dbml <COMMAND> [OPTIONS]

    COMMANDS:
        schemas     Generate Ecto schemas from a DBML file
        migrations  Generate Ecto migrations from a DBML file
        file        Generate DBML from Ecto schema files
        help        Show this help message

    EXAMPLES:
        dbml schemas schema.dbml -o lib/my_app/schema --namespace MyApp.Schema
        dbml migrations schema.dbml -o priv/repo/migrations -r MyApp.Repo
        dbml file lib/my_app/schema -o schema.dbml --project-name MyApp

    Run 'dbml <COMMAND> --help' for command-specific options.
    """)
  end

  defp print_schemas_help do
    IO.puts("""
    Generate Ecto schemas from a DBML file

    USAGE:
        dbml schemas <DBML_FILE> [OPTIONS]

    OPTIONS:
        -o, --output-dir DIR         Output directory for .ex files (required)
        -n, --namespace MODULE       Module namespace prefix (optional)
        --singularize true|false     Singularize table names (default: true)
        --update true|false          Allow overwriting existing files (default: false)
        --overwrite true|false       Allow overwriting existing files (default: false)
        -h, --help                   Show this help message

    EXAMPLES:
        dbml schemas schema.dbml -o lib/my_app/schema
        dbml schemas schema.dbml -o lib/my_app/schema --namespace MyApp.Schema --update true
        dbml schemas schema.dbml -o lib/my_app/schema --overwrite
    """)
  end

  defp print_migrations_help do
    IO.puts("""
    Generate Ecto migrations from a DBML file

    USAGE:
        dbml migrations <DBML_FILE> [OPTIONS]

    OPTIONS:
        -o, --output-dir DIR         Output directory for migration files (required)
        -r, --repo MODULE            Repo module name (required)
        --base-timestamp TIMESTAMP   Base timestamp for migrations (default: 20000101000000)
        --update true|false          Allow incremental updates (default: false)
        --overwrite true|false       Allow overwriting existing files (default: false)
        -h, --help                   Show this help message

    EXAMPLES:
        dbml migrations schema.dbml -o priv/repo/migrations -r MyApp.Repo
        dbml migrations schema.dbml -o priv/repo/migrations -r MyApp.Repo --update true
        dbml migrations schema.dbml -o priv/repo/migrations -r MyApp.Repo --overwrite
    """)
  end

  defp print_file_help do
    IO.puts("""
    Generate DBML from Ecto schema files

    USAGE:
        dbml file <SCHEMAS_DIR> [OPTIONS]

    OPTIONS:
        -o, --output FILE            Output path for .dbml file (required)
        --project-name NAME          Project name for DBML header (optional)
        --database-type TYPE         Database type (default: PostgreSQL)
        -h, --help                   Show this help message

    EXAMPLES:
        dbml file lib/my_app/schema -o schema.dbml
        dbml file lib/my_app/schema -o schema.dbml --project-name MyApp --database-type MySQL
    """)
  end
end
