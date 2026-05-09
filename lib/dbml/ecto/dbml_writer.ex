defmodule DBML.Ecto.DBMLWriter do
  @moduledoc false

  def write(tables, output_path, opts \\ []) do
    content = to_string(tables, opts)
    case File.write(output_path, content) do
      :ok -> {:ok, output_path}
      {:error, reason} -> {:error, reason}
    end
  end

  def to_string(tables, opts \\ []) do
    project_name = Keyword.get(opts, :project_name)
    database_type = Keyword.get(opts, :database_type, "PostgreSQL")

    lines = []

    # Add project block if project_name is provided
    lines =
      if project_name do
        lines ++ [
          "project #{project_name} {",
          "  database_type: \"#{database_type}\"",
          "}",
          ""
        ]
      else
        lines
      end

    # Collect all unique enums across tables
    enums = collect_enums(tables)

    # Emit enum blocks
    lines =
      if Enum.empty?(enums) do
        lines
      else
        enum_lines = enums |> render_enums() |> Enum.intersperse("")
        lines ++ enum_lines ++ [""]
      end

    # Topologically sort tables by FK dependencies
    sorted_tables = sort_tables_by_deps(tables)

    # Emit each table block
    table_lines =
      sorted_tables
      |> Enum.map(&render_table/1)
      |> Enum.intersperse("")

    lines = lines ++ table_lines

    # Collect and emit ref: statements
    refs = collect_refs(sorted_tables)

    lines =
      if Enum.empty?(refs) do
        lines
      else
        lines ++ [""] ++ refs
      end

    Enum.join(lines, "\n")
  end

  defp collect_enums(tables) do
    tables
    |> Enum.flat_map(fn table ->
      table.columns
      |> Enum.filter(& &1.is_enum)
      |> Enum.map(fn col ->
        {col.name, col.enum_values}
      end)
    end)
    |> Enum.uniq_by(&elem(&1, 0))
    |> Enum.into(%{})
  end

  defp render_enums(enums) do
    Enum.map(enums, fn {name, values} ->
      [
        "enum #{name} {",
        values |> Enum.map(&"  #{&1}") |> Enum.join("\n"),
        "}"
      ]
      |> Enum.join("\n")
    end)
  end

  defp sort_tables_by_deps(tables) do
    # Build dependency map: table_name => list of tables it depends on
    deps = build_dependencies(tables)

    # Topological sort
    case topological_sort(tables, deps) do
      {:ok, sorted} -> sorted
      :cycle -> tables
    end
  end

  defp build_dependencies(tables) do
    table_names = Enum.map(tables, & &1.name) |> MapSet.new()

    Enum.into(tables, %{}, fn table ->
      deps =
        table.columns
        |> Enum.filter(& &1.is_fk)
        |> Enum.map(& &1.fk_table)
        |> Enum.filter(&MapSet.member?(table_names, &1))
        |> Enum.uniq()

      {table.name, deps}
    end)
  end

  defp topological_sort(tables, deps) do
    table_names = Enum.map(tables, & &1.name)

    case topo_sort_iter(table_names, deps, []) do
      {:ok, sorted} ->
        {:ok,
         sorted
         |> Enum.map(fn name -> Enum.find(tables, &(&1.name == name)) end)
         |> Enum.reject(&is_nil/1)}

      :cycle ->
        :cycle
    end
  end

  defp topo_sort_iter(remaining, _deps, sorted) when remaining == [] do
    {:ok, Enum.reverse(sorted)}
  end

  defp topo_sort_iter(remaining, deps, sorted) do
    # Find tables with no unsatisfied dependencies
    ready =
      Enum.filter(remaining, fn table ->
        table_deps = Map.get(deps, table, [])
        Enum.all?(table_deps, &(!Enum.member?(remaining, &1)))
      end)

    case ready do
      [] -> :cycle
      ready_list ->
        next = hd(ready_list)
        new_remaining = List.delete(remaining, next)
        topo_sort_iter(new_remaining, deps, [next | sorted])
    end
  end

  defp render_table(table) do
    table_name = table.name

    lines = [
      "table #{table_name} {",
      render_columns(table) |> Enum.join("\n"),
      "}"
    ]

    Enum.join(lines, "\n")
  end

  defp render_columns(table) do
    lines = []

    # Add implicit id column for default primary key
    lines =
      if table.primary_key == :default do
        lines ++ ["  id int [pk]"]
      else
        lines
      end

    # Add other columns
    col_lines =
      table.columns
      |> Enum.flat_map(fn col ->
        attrs = render_column_attrs(col, table)

        if col.is_enum do
          ["  #{col.name} #{col.name}#{attrs}"]
        else
          ["  #{col.name} #{col.type}#{attrs}"]
        end
      end)

    lines ++ col_lines
  end

  defp render_column_attrs(col, table) do
    attrs = []

    # Primary key handling
    attrs =
      case table.primary_key do
        {:custom, pk_col, _type, autogenerate} when pk_col == col.name ->
          pk_attrs = if autogenerate, do: ["pk", "increment"], else: ["pk"]
          attrs ++ pk_attrs

        _ ->
          attrs
      end

    # Not null
    attrs =
      if col.null == false do
        attrs ++ ["not null"]
      else
        attrs
      end

    # Unique
    attrs =
      if col.unique do
        attrs ++ ["unique"]
      else
        attrs
      end

    # Default
    attrs =
      case col.default do
        nil ->
          attrs

        {:expression, expr} ->
          attrs ++ ["default: `#{expr}`"]

        val when is_binary(val) ->
          attrs ++ ["default: '#{val}'"]

        val ->
          attrs ++ ["default: #{inspect(val)}"]
      end

    # Foreign key rendering
    attrs =
      if col.is_fk do
        attrs ++ ["ref: > #{col.fk_table}.#{col.fk_col}"]
      else
        attrs
      end

    if Enum.empty?(attrs) do
      ""
    else
      " [" <> Enum.join(attrs, ", ") <> "]"
    end
  end

  defp collect_refs(tables) do
    tables
    |> Enum.flat_map(fn table ->
      table.columns
      |> Enum.filter(& &1.is_fk)
      |> Enum.map(fn col ->
        "ref: #{table.name}.#{col.name} > #{col.fk_table}.#{col.fk_col}"
      end)
    end)
  end
end
