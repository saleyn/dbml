defmodule Mix.Tasks.Dbml.Schemas do
  @shortdoc "Generate Ecto schemas from a DBML file"

  @moduledoc """
  Generates Ecto schema files from a DBML schema definition.

  ## Usage

      mix dbml.schemas <dbml_file> [options]

  ## Options

    * `-o, --output-dir DIR` - Output directory for generated .ex files (required)
    * `-n, --namespace MODULE` - Module namespace prefix (optional)
    * `--singularize` - Singularize table names (default: true)
    * `--update` - Allow overwriting existing files (default: false)
    * `-h, --help` - Show this help message

  ## Examples

      mix dbml.schemas schema.dbml -o lib/my_app/schema
      mix dbml.schemas schema.dbml -o lib/my_app/schema --namespace MyApp.Schema
      mix dbml.schemas schema.dbml -o lib/my_app/schema --update true

  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    case DBML.CLI.run(["schemas" | args]) do
      :ok ->
        :ok

      {:error, msg} ->
        Mix.raise(msg)
    end
  end
end
