defmodule DBML.Ecto.MigrationGenerator do
  @moduledoc false

  def generate(tokens, output_dir, repo_module, opts \\ []) do
    File.mkdir_p!(output_dir)
    base_timestamp = Keyword.get(opts, :base_timestamp, 20_000_101_000_000)
    update = Keyword.get(opts, :update, false)
    overwrite = Keyword.get(opts, :overwrite, false)

    alias_map = build_alias_map(tokens)
    refs = collect_refs(tokens, alias_map)
    tables = Keyword.get_values(tokens, :table)
    ordered_tables = order_tables_by_deps(tables, alias_map, refs)

    # Pre-flight check: ensure no files exist when update is false and overwrite is false
    with :ok <- check_file_exists(ordered_tables, output_dir, base_timestamp, update, overwrite) do
      cond do
        overwrite ->
          generate_all(ordered_tables, output_dir, repo_module, refs, base_timestamp)
        update ->
          generate_with_update(ordered_tables, output_dir, repo_module, refs, base_timestamp)
        true ->
          generate_all(ordered_tables, output_dir, repo_module, refs, base_timestamp)
      end
    end
  end

  defp check_file_exists(ordered_tables, output_dir, base_timestamp, update, overwrite) do
    if update || overwrite do
      :ok
    else
      migration_files =
        ordered_tables
        |> Enum.with_index(1)
        |> Enum.map(fn {table, index} ->
          timestamp = base_timestamp + index
          filename = migration_filename(timestamp, table.name)
          Path.join(output_dir, filename)
        end)

      case Enum.find(migration_files, &File.exists?/1) do
        nil -> :ok
        existing_path -> {:error, "File already exists: #{existing_path}"}
      end
    end
  end

  defp generate_all(ordered_tables, output_dir, repo_module, refs, base_timestamp) do
    paths =
      ordered_tables
      |> Enum.with_index(1)
      |> Enum.map(fn {table, index} ->
        timestamp = base_timestamp + index
        content = generate_migration(table, timestamp, repo_module, refs)
        filename = migration_filename(timestamp, table.name)
        path = Path.join(output_dir, filename)
        File.write!(path, content)
        path
      end)

    {:ok, paths}
  end

  defp generate_with_update(ordered_tables, output_dir, repo_module, refs, base_timestamp) do
    # Find the highest timestamp in existing migrations
    max_existing_timestamp =
      case File.ls(output_dir) do
        {:ok, files} ->
          files
          |> Enum.filter(&String.match?(&1, ~r/^\d+_/))
          |> Enum.map(&String.slice(&1, 0..13))
          |> Enum.map(&String.to_integer/1)
          |> Enum.max(fn -> 0 end)

        {:error, _} ->
          0
      end

    # For update mode, check if migrations exist and compare content
    {paths, _next_timestamp} =
      ordered_tables
      |> Enum.with_index(1)
      |> Enum.reduce({[], max_existing_timestamp + 1}, fn {table, index}, {acc_paths, next_ts} ->
        timestamp = base_timestamp + index
        content = generate_migration(table, timestamp, repo_module, refs)
        filename = migration_filename(timestamp, table.name)
        path = Path.join(output_dir, filename)

        # Check if file exists and has same content
        if File.exists?(path) do
          existing_content = File.read!(path)
          if existing_content == content do
            # Content unchanged, skip
            {acc_paths, next_ts}
          else
            # Content changed, write new file with incremented timestamp
            new_filename = migration_filename(next_ts, table.name)
            new_path = Path.join(output_dir, new_filename)
            File.write!(new_path, content)
            {[new_path | acc_paths], next_ts + 1}
          end
        else
          # File doesn't exist, create it
          File.write!(path, content)
          {[path | acc_paths], next_ts}
        end
      end)

    {:ok, Enum.reverse(paths)}
  end

  defp build_alias_map(tokens) do
    tokens
    |> Keyword.get_values(:table)
    |> Enum.filter(&Map.has_key?(&1, :alias))
    |> Enum.into(%{}, fn t -> {t.alias, t.name} end)
  end

  defp collect_refs(tokens, alias_map) do
    resolve = fn name -> Map.get(alias_map, name, name) end

    standalone =
      tokens
      |> Keyword.get_values(:ref)
      |> List.flatten()
      |> Enum.map(fn ref ->
        owner_table = resolve.(ref.owner.table)
        owner_col = ref.owner.column
        rel_table = resolve.(ref.related.table)
        rel_col = ref.related.column
        {{owner_table, owner_col}, {ref.type, rel_table, rel_col}}
      end)

    inline =
      tokens
      |> Keyword.get_values(:table)
      |> Enum.flat_map(fn table ->
        table_name = table.name
        fields = table.fields || []

        fields
        |> Enum.flat_map(fn col ->
          case Map.get(col, :reference) do
            nil ->
              []

            ref ->
              rel_table = resolve.(ref.related.table)
              rel_col = ref.related.column
              [{{table_name, col.name}, {ref.type, rel_table, rel_col}}]
          end
        end)
      end)

    Map.new(standalone ++ inline)
  end

  defp order_tables_by_deps(tables, alias_map, refs) do
    resolve = fn name -> Map.get(alias_map, name, name) end

    # Build dependency map: table_name => list of tables it depends on
    deps = build_dependencies(tables, refs, resolve)

    # Topological sort
    case topological_sort(tables, deps) do
      {:ok, sorted} -> sorted
      :cycle -> tables  # fallback to original order if there's a cycle
    end
  end

  defp build_dependencies(tables, refs, resolve) do
    table_names = Enum.map(tables, & &1.name) |> MapSet.new()

    Enum.into(tables, %{}, fn table ->
      name = table.name
      fields = table.fields || []

      deps =
        fields
        |> Enum.flat_map(fn col ->
          case Map.get(col, :reference) do
            nil ->
              case Map.get(refs, {name, col.name}) do
                {_, rel_table, _} ->
                  if MapSet.member?(table_names, rel_table), do: [rel_table], else: []

                nil ->
                  []
              end

            ref ->
              rel_table = resolve.(ref.related.table)
              if MapSet.member?(table_names, rel_table), do: [rel_table], else: []
          end
        end)
        |> Enum.uniq()

      {name, deps}
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

  defp migration_filename(timestamp, table_name) do
    table_snake = table_name |> String.replace(" ", "_") |> String.downcase()
    "#{timestamp}_create_#{table_snake}.exs"
  end

  defp generate_migration(table, _timestamp, repo_module, refs) do
    table_name = table.name
    table_snake = table_name |> String.replace(" ", "_") |> String.downcase()
    columns = table.fields || []
    indexes = Map.get(table, :indexes) || []

    col_names = Enum.map(columns, & &1.name)
    has_timestamps = "created_at" in col_names and "updated_at" in col_names

    pk_cols = get_pk_columns(columns)
    # Check for composite PK in indexes as well
    index_pk_cols = get_index_pk_columns(indexes)
    all_pk_cols = if Enum.empty?(index_pk_cols), do: pk_cols, else: index_pk_cols
    composite_pk = has_composite_pk(all_pk_cols)
    {primary_key_opt, skip_id} = determine_pk_opt(columns, composite_pk, all_pk_cols)

    # For composite PKs, we don't skip the columns; they're added as regular fields
    # For standard single id PK, we skip it since Ecto provides it by default
    skip_set =
      MapSet.new(
        (if composite_pk, do: [], else: pk_cols) ++
          if(has_timestamps, do: ["created_at", "updated_at"], else: [])
      )

    skip_set = if skip_id, do: MapSet.put(skip_set, "id"), else: skip_set

    column_lines = generate_column_lines(columns, table_name, skip_set, refs)
    index_lines = generate_index_lines(table_snake, indexes)
    fk_index_lines = generate_fk_indexes(table_snake, columns, table_name, refs)

    # Deduplicate index lines
    all_index_lines = (fk_index_lines ++ index_lines) |> Enum.uniq()

    create_table_opts = if primary_key_opt, do: ", #{primary_key_opt}", else: ""

    lines =
      ["defmodule #{repo_module}.Migrations.Create#{to_pascal(table_snake)} do",
       "  use Ecto.Migration",
       "",
       "  def change do",
       "    create table(:#{table_snake}#{create_table_opts}) do"] ++
      column_lines ++
      (if has_timestamps, do: ["", "      timestamps()"], else: []) ++
      ["    end",
       ""] ++
      all_index_lines ++
      ["  end",
       "end",
       ""]

    Enum.join(lines, "\n")
  end

  defp get_pk_columns(columns) do
    columns
    |> Enum.filter(fn col ->
      Map.get(col, :primary) == true
    end)
    |> Enum.map(& &1.name)
  end

  defp get_index_pk_columns(indexes) do
    Enum.find_value(indexes, [], fn idx ->
      if Map.get(idx, :primary) do
        idx.columns
      else
        false
      end
    end)
  end

  defp has_composite_pk(pk_cols) do
    length(pk_cols) > 1
  end

  defp determine_pk_opt(_columns, composite_pk, pk_cols) do
    if composite_pk || (length(pk_cols) == 1 && hd(pk_cols) != "id") do
      {"primary_key: false", length(pk_cols) > 0 && hd(pk_cols) == "id"}
    else
      {nil, false}
    end
  end

  defp generate_column_lines(columns, table_name, skip_set, refs) do
    columns
    |> Enum.flat_map(fn col ->
      col_name = col.name

      if MapSet.member?(skip_set, col_name) do
        []
      else
        col_name_atom = col_name |> String.replace(" ", "_") |> String.downcase()
        ref_key = {table_name, col_name}

        case Map.get(refs, ref_key) do
          {_, related_table, related_col} ->
            related_table_snake =
              related_table |> String.replace(" ", "_") |> String.downcase()

            ["      add :#{col_name_atom}, references(:#{related_table_snake}, column: :#{related_col})"]

          nil ->
            col_type = col.type
            type_atom = map_type(col_type)
            opts = build_column_opts(col)
            ["      add :#{col_name_atom}, #{type_atom}#{opts}"]
        end
      end
    end)
  end

  defp build_column_opts(col) do
    opts = []

    opts =
      if Map.get(col, :null) == false do
        opts ++ ["null: false"]
      else
        opts
      end

    opts =
      if Map.get(col, :unique) do
        opts ++ ["unique: true"]
      else
        opts
      end

    opts =
      case Map.get(col, :default) do
        nil ->
          opts

        {:expression, expr} ->
          opts ++ ["default: fragment(\"#{expr}\")"]

        val when is_binary(val) ->
          opts ++ ["default: \"#{val}\""]

        val ->
          opts ++ ["default: #{inspect(val)}"]
      end

    if opts == [] do
      ""
    else
      ", " <> Enum.join(opts, ", ")
    end
  end

  defp generate_fk_indexes(table_snake, columns, table_name, refs) do
    # Find all FK columns
    fk_cols =
      columns
      |> Enum.flat_map(fn col ->
        col_name = col.name
        ref_key = {table_name, col_name}

        if Map.has_key?(refs, ref_key) do
          [col_name |> String.replace(" ", "_") |> String.downcase()]
        else
          []
        end
      end)

    # Create indexes for FK columns
    fk_cols
    |> Enum.map(fn col -> "    create index(:#{table_snake}, [:#{col}])" end)
  end

  defp generate_index_lines(table_snake, indexes) do
    indexes
    |> Enum.flat_map(fn idx ->
      cols = idx.columns

      # Skip primary key indexes as they're handled via primary_key opt
      if Map.get(idx, :primary) do
        []
      else
        cols_str = "[" <> Enum.join(Enum.map(cols, &":#{&1}"), ", ") <> "]"

        if Map.get(idx, :unique) do
          ["    create unique_index(:#{table_snake}, #{cols_str})"]
        else
          ["    create index(:#{table_snake}, #{cols_str})"]
        end
      end
    end)
  end

  defp map_type(type_str) do
    case String.downcase(type_str) do
      t when t in ["int", "integer", "smallint", "bigint"] -> ":integer"
      t when t in ["varchar", "char", "text", "character varying"] -> ":string"
      t when t in ["boolean", "bool"] -> ":boolean"
      t when t in ["float", "double", "real"] -> ":float"
      t when t in ["decimal", "numeric"] -> ":decimal"
      "date" -> ":date"
      t when t in ["datetime", "timestamp", "timestamptz", "timestamp with time zone"] -> ":datetime"
      "time" -> ":time"
      "uuid" -> ":uuid"
      t when t in ["json", "jsonb"] -> ":map"
      t when t in ["serial", "bigserial"] -> ":integer"
      _ -> ":string"
    end
  end

  defp to_pascal(name) do
    name
    |> String.split(~r/[_\s]+/)
    |> Enum.map(&String.capitalize/1)
    |> Enum.join()
  end
end
