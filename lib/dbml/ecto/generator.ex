defmodule DBML.Ecto.Generator do
  @moduledoc false

  def generate(tokens, output_dir, namespace, singularize \\ true, update \\ false) do
    File.mkdir_p!(output_dir)
    alias_map = build_alias_map(tokens)
    refs = collect_refs(tokens, alias_map)
    enums_map = collect_enums(tokens)

    # Compute file paths and content
    files_to_write =
      tokens
      |> Keyword.get_values(:table)
      |> Enum.map(fn table ->
        content = generate_schema(table, namespace, refs, enums_map, singularize)
        filename = table[:name] |> String.replace(" ", "_") |> String.downcase() |> Kernel.<>(".ex")
        path = Path.join(output_dir, filename)
        {path, content}
      end)

    # Pre-flight check: ensure no files exist when update is false
    unless update do
      case Enum.find(files_to_write, fn {path, _} -> File.exists?(path) end) do
        {existing_path, _} ->
          {:error, "File already exists: #{existing_path}"}

        nil ->
          write_all(files_to_write)
      end
    else
      write_all(files_to_write)
    end
  end

  defp write_all(files_to_write) do
    paths =
      files_to_write
      |> Enum.map(fn {path, content} ->
        File.write!(path, content)
        path
      end)

    {:ok, paths}
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

  defp collect_enums(tokens) do
    tokens
    |> Keyword.get_values(:enum)
    |> Enum.into(%{}, fn enum ->
      values = enum[:values] |> Enum.map(& &1[:value])
      {enum[:name], values}
    end)
  end

  defp generate_schema(table, namespace, refs, enums_map, singularize) do
    table_name = table[:name]
    definitions = table[:definitions]
    columns = Keyword.get_values(definitions, :column)
    indexes = Keyword.get(definitions, :indexes) || []
    col_names = Enum.map(columns, & &1[:name])

    has_timestamps = "created_at" in col_names and "updated_at" in col_names

    {pk_annotation, skip_pk_names} = determine_pk(columns, indexes)

    skip_set =
      MapSet.new(
        skip_pk_names ++
          if(has_timestamps, do: ["created_at", "updated_at"], else: [])
      )

    field_lines = generate_field_lines(columns, table_name, skip_set, refs, enums_map, namespace, singularize)

    module_base_name = if singularize, do: singularize(table_name), else: table_name
    module_name = namespace <> "." <> to_pascal(module_base_name)

    pk_attr_lines = if pk_annotation, do: ["  #{pk_annotation}", ""], else: []

    lines =
      ["defmodule #{module_name} do",
       "  use Ecto.Schema",
       ""] ++
      pk_attr_lines ++
      [~s(  schema "#{table_name}" do)] ++
      field_lines ++
      (if has_timestamps, do: ["", "    timestamps()"], else: []) ++
      ["  end",
       "end",
       ""]

    Enum.join(lines, "\n")
  end

  defp determine_pk(columns, _indexes) do
    integer_types = ["int", "integer", "serial", "bigserial"]
    serial_types = ["serial", "bigserial"]

    col_pks = Enum.filter(columns, fn col ->
      settings = col[:settings] || []
      Keyword.get(settings, :primary, false)
    end)

    cond do
      col_pks == [] ->
        {"@primary_key false", []}

      length(col_pks) == 1 ->
        pk = hd(col_pks)
        is_standard = pk[:name] == "id" and pk[:type] in integer_types

        if is_standard do
          {nil, ["id"]}
        else
          ecto_type =
            cond do
              pk[:type] in ["int", "integer"] -> ":integer"
              pk[:type] in serial_types -> ":id"
              pk[:type] == "uuid" -> ":binary_id"
              pk[:type] in ["varchar", "char", "text"] -> ":string"
              true -> ":string"
            end

          settings = pk[:settings] || []
          autogen = Keyword.get(settings, :autoincrement, false) or pk[:type] in serial_types

          annotation = "@primary_key {:#{pk[:name]}, #{ecto_type}, autogenerate: #{autogen}}"
          {annotation, [pk[:name]]}
        end

      true ->
        {"@primary_key false", []}
    end
  end

  defp generate_field_lines(columns, table_name, skip_set, refs, enums_map, namespace, singularize) do
    columns
    |> Enum.flat_map(fn col ->
      col_name = col[:name]

      if MapSet.member?(skip_set, col_name) do
        []
      else
        col_name_atom = col_name |> String.replace(" ", "_") |> String.downcase()
        ref_key = {table_name, col_name}

        case Map.get(refs, ref_key) do
          {type, related_table, _} when type in [:many_to_one, :one_to_one] ->
            assoc_name = if singularize, do: singularize(related_table), else: related_table
            related_module_base = if singularize, do: singularize(related_table), else: related_table
            related_module = "#{namespace}.#{to_pascal(related_module_base)}"
            ["    belongs_to :#{assoc_name}, #{related_module}, foreign_key: :#{col_name_atom}"]

          _ ->
            col_type = col[:type]

            case Map.get(enums_map, col_type) do
              nil ->
                ["    field :#{col_name_atom}, #{map_type(col_type)}"]

              values ->
                vals_str = Enum.map(values, &":#{&1}") |> Enum.join(", ")
                ["    field :#{col_name_atom}, Ecto.Enum, values: [#{vals_str}]"]
            end
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
      t when t in ["datetime", "timestamp", "timestamptz", "timestamp with time zone"] -> ":naive_datetime"
      "time" -> ":time"
      "uuid" -> ":binary_id"
      t when t in ["json", "jsonb"] -> ":map"
      t when t in ["serial", "bigserial"] -> ":integer"
      _ -> ":string"
    end
  end

  defp singularize(name) do
    cond do
      String.ends_with?(name, "ies") ->
        name |> String.trim_trailing("ies") |> Kernel.<>("y")

      String.ends_with?(name, "ses") ->
        name |> String.trim_trailing("ses") |> Kernel.<>("s")

      String.ends_with?(name, "xes") ->
        name |> String.trim_trailing("xes") |> Kernel.<>("x")

      String.ends_with?(name, "zes") ->
        name |> String.trim_trailing("zes") |> Kernel.<>("z")

      String.ends_with?(name, "ches") ->
        name |> String.trim_trailing("ches") |> Kernel.<>("ch")

      String.ends_with?(name, "shes") ->
        name |> String.trim_trailing("shes") |> Kernel.<>("sh")

      String.ends_with?(name, "s") ->
        name |> String.trim_trailing("s")

      true ->
        name
    end
  end

  defp to_pascal(name) do
    name
    |> String.split(~r/[_\s]+/)
    |> Enum.map(&String.capitalize/1)
    |> Enum.join()
  end
end
