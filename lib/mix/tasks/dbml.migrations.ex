defmodule Mix.Tasks.Dbml.Migrations do
  @shortdoc "Generate Ecto migrations from a DBML file"

  @moduledoc """
  Generates Ecto migration files from a DBML schema definition.

  ## Usage

      mix dbml.migrations <dbml_file> [options]

  ## Options

    * `-o, --output-dir DIR` - Output directory for migration files (required)
    * `-r, --repo MODULE` - Repo module name (required)
    * `--base-timestamp TIMESTAMP` - Base timestamp for migrations (default: 20000101000000)
    * `--update` - Allow incremental updates (default: false)
    * `-h, --help` - Show this help message

  ## Examples

      mix dbml.migrations schema.dbml -o priv/repo/migrations -r MyApp.Repo
      mix dbml.migrations schema.dbml -o priv/repo/migrations -r MyApp.Repo --update true

  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    case DBML.CLI.run(["migrations" | args]) do
      :ok ->
        :ok

      {:error, msg} ->
        Mix.raise(msg)
    end
  end
end
