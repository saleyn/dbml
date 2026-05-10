defmodule Mix.Tasks.Dbml.File do
  @shortdoc "Generate DBML from Ecto schema files"

  @moduledoc """
  Generates a DBML schema file from existing Ecto schema files.

  This is the reverse operation: reads Ecto schemas and produces DBML.

  ## Usage

      mix dbml.file <schemas_dir> [options]

  ## Options

    * `-o, --output FILE` - Output path for the .dbml file (required)
    * `--project-name NAME` - Project name for DBML header (optional)
    * `--database-type TYPE` - Database type (default: PostgreSQL)
    * `-h, --help` - Show this help message

  ## Examples

      mix dbml.file lib/my_app/schema -o schema.dbml
      mix dbml.file lib/my_app/schema -o schema.dbml --project-name MyApp
      mix dbml.file lib/my_app/schema -o schema.dbml --project-name MyApp --database-type MySQL

  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    case DBML.CLI.run(["file" | args]) do
      :ok ->
        :ok

      {:error, msg} ->
        Mix.raise(msg)
    end
  end
end
