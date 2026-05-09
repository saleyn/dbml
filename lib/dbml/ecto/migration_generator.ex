defmodule DBML.Ecto.MigrationGenerator do
  @moduledoc false

  def generate(tokens, output_dir, repo_module, opts \\ []) do
    File.mkdir_p!(output_dir)
    base_timestamp = Keyword.get(opts, :base_timestamp, 20_000_101_000_000)
    update = Keyword.get(opts, :update, false)

    alias_map = build_alias_map(tokens)
    refs = collect_refs(tokens, alias_map)
    tables = Keyword.get_values(tokens, :table)
    ordered_tables = order_tables_by_deps(tables, alias_map, refs)

    # Pre-compute content for all tables
    migrations_to_write =
      ordered_tables
      |> Enum.with_index(1)
      |> Enum.map(fn {table, index} ->
        table_snake = table[:name] |> String.replace(" ", "_") |> String.downcase()
        content = generate_migration(table, base_timestamp + index, repo_module, refs)
        {table_snake, table, index, content}
      end)

    if update do
      write_migrations_with_update(migrations_to_write, output_dir, base_timestamp, repo_module, refs)
    else
      write_migrations_no_update(migrations_to_write, output_dir, base_timestamp)
    end
  end

  defp write_migrations_no_update(migrations_to_write, output_dir, base_timestamp) do
    # Pre-flight check: ensure no files exist
    case Enum.with_index(migrations_to_write, 1)
         |> Enum.find(fn {{table_snake, _, _index, _content}, seq} ->
           path = Path.join(output_dir, "#{base_timestamp + seq}_create_#{table_snake}.exs")
           File.exists?(path)
         end) do
      {{table_snake, _, _, _}, seq} ->
        existing_path = Path.join(output_dir, "#{base_timestamp + seq}_create_#{table_snake}.exs")
        {:error, "File already exists: #{existing_path}"}

      nil ->
        # All clear, write all files
        paths =
          migrations_to_write
          |> Enum.with_index(1)
          |> Enum.map(fn {{table_snake, _table, _index, content}, seq} ->
            timestamp = base_timestamp + seq
            filename = "#{timestamp}_create_#{table_snake}.exs"
            path = Path.join(output_dir, filename)
            File.write!(path, content)
            path
          end)

        {:ok, paths}
    end
  end

  defp write_migrations_with_update(migrations_to_write, output_dir, base_timestamp, _repo_module, _refs) do
    existing_migrations = find_existing_migrations(output_dir)
    max_ts = max_timestamp(output_dir, base_timestamp)
    next_new_ts = max_ts + 1

    {paths_written, _next_ts} =
      migrations_to_write
      |> Enum.with_index(1)
      |> Enum.reduce({[], next_new_ts}, fn {{table_snake, _table, _index, content}, seq}, {paths, ts} ->
        case Map.get(existing_migrations, table_snake) do
          # File exists and content matches — skip
          {_existing_path, ^content} ->
            {paths, ts}

          # File exists but content changed — write new migration
          {_existing_path, _old_content} ->
            filename = "#{ts}_create_#{table_snake}.exs"
            path = Path.join(output_dir, filename)
            File.write!(path, content)
            {paths ++ [path], ts + 1}

          # No existing file — write new migration
          nil ->
            timestamp = base_timestamp + seq
            filename = "#{timestamp}_create_#{table_snake}.exs"
            path = Path.join(output_dir, filename)
            File.write!(path, content)
            {paths ++ [path], ts}
        end
      end)

    {:ok, paths_written}
  end

  defp find_existing_migrations(output_dir) do
    output_dir
    |> File.ls!()
    |> Enum.filter(&String.match?(&1, ~r/^\d+_create_.+\.exs$/))
    |> Enum.into(%{}, fn filename ->
      path = Path.join(output_dir, filename)
      content = File.read!(path)
      # Extract table name from filename like "20000101000001_create_users.exs"
      # Pattern: NNNNNNNNNNNNNN_create_<table>.exs (14 digits + 8 chars for _create_)
      table_snake =
        filename
        |> String.slice(22..-5//1)  # Skip "NNNNNNNNNNNNNN_create_" (22 chars) and ".exs" (4 chars)

      {table_snake, {path, content}}
    end)
  rescue
    File.Error -> %{}
  end

  defp max_timestamp(output_dir, base_timestamp) do
    output_dir
    |> File.ls!()
    |> Enum.filter(&String.match?(&1, ~r/^\d+_/))
    |> Enum.map(fn filename ->
      filename
      |> String.slice(0..13)
      |> String.to_integer()
    end)
    |> case do
      [] -> base_timestamp
      timestamps -> Enum.max(timestamps)
    end
  rescue
    File.Error -> base_timestamp
  end

  defp build_alias_map(tokens) do
    tokens
    |> Keyword.get_values(:table)
    |> Enum.filter(&Keyword.has_key?(&1, :alias))
    |> Enum.into(%{}, fn t -> {t[:alias], t[:name]} end)
  end

  defp collect_refs(tokens, alias_map) do
    resolve = fn name -> Map.get(alias_map, name, name) end

    standalone =
      tokens
      |> Keyword.get_values(:ref)
      |> Enum.map(fn ref ->
        owner_table = resolve.(ref[:owner][:table])
        owner_col = ref[:owner][:column]
        rel_table = resolve.(ref[:related][:table])
        rel_col = ref[:related][:column]
        {{owner_table, owner_col}, {ref[:type], rel_table, rel_col}}
      end)

    inline =
      tokens
      |> Keyword.get_values(:table)
      |> Enum.flat_map(fn table ->
        table_name = table[:name]

        table[:definitions]
        |> Keyword.get_values(:column)
        |> Enum.flat_map(fn col ->
          settings = col[:settings] || []

          case Keyword.get(settings, :reference) do
            nil ->
              []

            ref ->
              rel_table = resolve.(ref[:related][:table])
              rel_col = ref[:related][:column]
              [{{table_name, col[:name]}, {ref[:type], rel_table, rel_col}}]
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
    table_names = Enum.map(tables, & &1[:name]) |> MapSet.new()

    Enum.into(tables, %{}, fn table ->
      name = table[:name]
      definitions = table[:definitions]

      deps =
        Keyword.get_values(definitions, :column)
        |> Enum.flat_map(fn col ->
          settings = col[:settings] || []

          case Keyword.get(settings, :reference) do
            nil ->
              case Map.get(refs, {name, col[:name]}) do
                {_, rel_table, _} ->
                  if MapSet.member?(table_names, rel_table), do: [rel_table], else: []

                nil ->
                  []
              end

            ref ->
              rel_table = resolve.(ref[:related][:table])
              if MapSet.member?(table_names, rel_table), do: [rel_table], else: []
          end
        end)
        |> Enum.uniq()

      {name, deps}
    end)
  end

  defp topological_sort(tables, deps) do
    table_names = Enum.map(tables, & &1[:name])

    case topo_sort_iter(table_names, deps, []) do
      {:ok, sorted} ->
        {:ok,
         sorted
         |> Enum.map(fn name -> Enum.find(tables, &(&1[:name] == name)) end)
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

  defp generate_migration(table, _timestamp, repo_module, refs) do
    table_name = table[:name]
    table_snake = table_name |> String.replace(" ", "_") |> String.downcase()
    definitions = table[:definitions]
    columns = Keyword.get_values(definitions, :column)
    indexes = Keyword.get(definitions, :indexes) || []

    col_names = Enum.map(columns, & &1[:name])
    has_timestamps = "created_at" in col_names and "updated_at" in col_names

    pk_cols = get_pk_columns(columns, indexes)
    composite_pk = has_composite_pk(pk_cols)
    {primary_key_opt, skip_id} = determine_pk_opt(columns, composite_pk, pk_cols)

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
    fk_index_lines = generate_fk_indexes(table_snake, columns, indexes, table_name, refs)

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
      fk_index_lines ++
      index_lines ++
      ["  end",
       "end",
       ""]

    Enum.join(lines, "\n")
  end

  defp get_pk_columns(columns, indexes) do
    col_pks =
      columns
      |> Enum.filter(fn col ->
        settings = col[:settings] || []
        Keyword.get(settings, :primary, false)
      end)
      |> Enum.map(& &1[:name])

    if col_pks != [] do
      col_pks
    else
      # Check for composite PK in indexes
      Enum.find_value(indexes, [], fn idx ->
        if Keyword.get(idx[:options] || [], :primary, false) do
          idx[:columns]
        else
          false
        end
      end)
    end
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
      col_name = col[:name]

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
            col_type = col[:type]
            type_atom = map_type(col_type)
            settings = col[:settings] || []
            opts = build_column_opts(settings)
            ["      add :#{col_name_atom}, #{type_atom}#{opts}"]
        end
      end
    end)
  end

  defp build_column_opts(settings) do
    opts = []

    opts =
      if settings[:null] == false do
        opts ++ ["null: false"]
      else
        opts
      end

    opts =
      if settings[:unique] do
        opts ++ ["unique: true"]
      else
        opts
      end

    opts =
      case settings[:default] do
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

  defp generate_fk_indexes(table_snake, columns, indexes, table_name, refs) do
    # Find all FK columns
    fk_cols =
      columns
      |> Enum.flat_map(fn col ->
        col_name = col[:name]
        ref_key = {table_name, col_name}

        if Map.has_key?(refs, ref_key) do
          [col_name |> String.replace(" ", "_") |> String.downcase()]
        else
          []
        end
      end)

    # Check which columns already have indexes
    indexed_cols = get_indexed_columns(indexes)

    # Create indexes for FK columns not already indexed
    fk_cols
    |> Enum.reject(fn col -> Enum.member?(indexed_cols, [col]) end)
    |> Enum.map(fn col -> "    create index(:#{table_snake}, [:#{col}])" end)
  end

  defp generate_index_lines(table_snake, indexes) do
    indexes
    |> Enum.flat_map(fn idx ->
      cols = idx[:columns]
      opts = idx[:options] || []

      # Skip primary key indexes as they're handled via primary_key opt
      if opts[:primary] do
        []
      else
        cols_str = "[" <> Enum.join(Enum.map(cols, &":#{&1}"), ", ") <> "]"

        if opts[:unique] do
          ["    create unique_index(:#{table_snake}, #{cols_str}#{format_index_opts(opts)})"]
        else
          ["    create index(:#{table_snake}, #{cols_str}#{format_index_opts(opts)})"]
        end
      end
    end)
  end

  defp format_index_opts(opts) do
    extra_opts =
      opts
      |> Enum.reject(fn {k, _} -> k in [:unique, :primary] end)
      |> Enum.map(fn {k, v} -> "#{k}: #{inspect(v)}" end)

    if extra_opts == [] do
      ""
    else
      ", " <> Enum.join(extra_opts, ", ")
    end
  end

  defp get_indexed_columns(indexes) do
    Enum.map(indexes, & &1[:columns])
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
