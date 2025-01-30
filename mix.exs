defmodule DBML.MixProject do
  use Mix.Project

  def project() do
    [
      app: :dbml,
      version: "0.2.0",
      elixir: "~> 1.15",
      deps: deps(),
      package: package()
    ]
  end

  def application(), do: []

  defp deps() do
    [
      {:nimble_parsec, "~> 1.4"}
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
