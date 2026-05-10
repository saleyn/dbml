defmodule DBML.CLI do
  @moduledoc """
  CLI entry point for DBML. Provides both escript (main/1) and programmatic (run/1) interfaces.
  """

  @schemas_switches [
    output_dir: :string,
    namespace: :string,
    update: :boolean,
    singularize: :boolean,
    help: :boolean
  ]

  @schemas_aliases [
    o: :output_dir,
    n: :namespace,
    h: :help
  ]

  @migrations_switches [
    output_dir: :string,
    repo: :string,
    base_timestamp: :integer,
    update: :boolean,
    help: :boolean
  ]

  @migrations_aliases [
    o: :output_dir,
    r: :repo,
    h: :help
  ]

  @file_switches [
    output: :string,
    project_name: :string,
    database_type: :string,
    help: :boolean
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

  def run(["help" | _]) do
    print_help()
    :ok
  end

  def run(["schemas" | rest]) do
    run_schemas(rest)
  end

  def run(["migrations" | rest]) do
    run_migrations(rest)
  end

  def run(["file" | rest]) do
    run_file(rest)
  end

  def run([unknown | _]) do
    {:error, "Unknown command: #{unknown}. Run 'dbml help' for usage."}
  end

  defp run_schemas(args) do
    {opts, positional, _invalid} = OptionParser.parse(args, switches: @schemas_switches, aliases: @schemas_aliases)

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
         {:output_dir, output_dir} when not is_nil(output_dir) <- {:output_dir, opts[:output_dir]},
         gen_opts <- build_schemas_opts(opts),
         {:ok, paths} <- DBML.generate_ecto_schemas(tokens, output_dir, gen_opts) do
      Enum.each(paths, &IO.puts("Generated: #{&1}"))
      :ok
    else
      {:file_exists, false} ->
        {:error, "DBML file not found: #{dbml_file}"}

      {:output_dir, nil} ->
        {:error, "schemas requires --output-dir (-o) option"}

      {:error, reason} ->
        {:error, format_error(reason)}
    end
  end

  defp run_migrations(args) do
    {opts, positional, _invalid} = OptionParser.parse(args, switches: @migrations_switches, aliases: @migrations_aliases)

    if opts[:help] do
      print_migrations_help()
      :ok
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
         {:output_dir, output_dir} when not is_nil(output_dir) <- {:output_dir, opts[:output_dir]},
         {:repo, repo} when not is_nil(repo) <- {:repo, opts[:repo]},
         gen_opts <- build_migrations_opts(opts),
         {:ok, paths} <- DBML.generate_ecto_migrations(tokens, output_dir, repo, gen_opts) do
      Enum.each(paths, &IO.puts("Generated: #{&1}"))
      :ok
    else
      {:file_exists, false} ->
        {:error, "DBML file not found: #{dbml_file}"}

      {:output_dir, nil} ->
        {:error, "migrations requires --output-dir (-o) option"}

      {:repo, nil} ->
        {:error, "migrations requires --repo (-r) option"}

      {:error, reason} ->
        {:error, format_error(reason)}
    end
  end

  defp run_file(args) do
    {opts, positional, _invalid} = OptionParser.parse(args, switches: @file_switches, aliases: @file_aliases)

    if opts[:help] do
      print_file_help()
      :ok
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
      :ok
    else
      {:dir_exists, false} ->
        {:error, "Schemas directory not found: #{schemas_dir}"}

      {:output, nil} ->
        {:error, "file requires --output (-o) option"}

      {:error, reason} ->
        {:error, format_error(reason)}
    end
  end

  defp build_schemas_opts(opts) do
    []
    |> add_opt(opts, :namespace, :namespace)
    |> add_opt(opts, :singularize, :singularize)
    |> add_opt(opts, :update, :update)
  end

  defp build_migrations_opts(opts) do
    []
    |> add_opt(opts, :base_timestamp, :base_timestamp)
    |> add_opt(opts, :update, :update)
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

  defp format_error(%{input: _, location: _, position: _} = err) do
    "Parse error at position #{err.position}: #{err.input}"
  end

  defp format_error(reason) when is_binary(reason) do
    reason
  end

  defp format_error(reason) do
    inspect(reason)
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

    :ok
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
        -h, --help                   Show this help message

    EXAMPLES:
        dbml schemas schema.dbml -o lib/my_app/schema
        dbml schemas schema.dbml -o lib/my_app/schema --namespace MyApp.Schema --update true
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
        -h, --help                   Show this help message

    EXAMPLES:
        dbml migrations schema.dbml -o priv/repo/migrations -r MyApp.Repo
        dbml migrations schema.dbml -o priv/repo/migrations -r MyApp.Repo --update true
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
