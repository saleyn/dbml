# DBML

A parser implementation for the Database Markup Language (DBML) syntax.

DBML documentation:
  * [DBML Syntax](https://dbml.dbdiagram.io/docs)
  * [DBML Visualization](https://dbml.dbdiagram.io/home) 

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `dbml` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:dbml, "~> 0.2"}
  ]
end
```

## Usage

```elixir
{:ok, dbml} = DBML.parse_file(filename)
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at [https://hexdocs.pm/dbml](https://hexdocs.pm/dbml).

