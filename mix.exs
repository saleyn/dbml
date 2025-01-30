defmodule DBML.MixProject do
  use Mix.Project

  def project() do
    [
      app: :dbml,
      version: "0.2.0",
      elixir: "~> 1.15",
      description: "Database Markup Language (DBML) Parser",
      deps: deps(),
      package: package(),
      docs: [
        # The main page in the docs
        main: "readme",
        extras: ["README.md"]
      ]
    ]
  end

  def application(), do: []

  defp deps() do
    [
      {:nimble_parsec, "~> 1.4"},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false}
    ]
  end

  defp package() do
    [
      licenses: ["Apache 2.0"],
      links: %{"GitHub" => "https://github.com/saleyn/dbml-ex"},
      files: ~w(lib test mix.* Makefile README.md)
    ]
  end
end
