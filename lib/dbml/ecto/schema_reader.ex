defmodule DBML.Ecto.SchemaReader do
  @moduledoc false

  defstruct [
    name: nil,
    module: nil,
    primary_key: :default,
    columns: [],
    has_timestamps: false
  ]

  defmodule Column do
    defstruct [
      name: nil,
      type: nil,
      is_fk: false,
      fk_table: nil,
      fk_col: nil,
      null: nil,
      unique: nil,
      default: nil,
      is_enum: false,
      enum_values: []
    ]
  end

  def read_dir(dir) do
    case File.ls(dir) do
      {:ok, files} ->
        ex_files = Enum.filter(files, &String.ends_with?(&1, ".ex"))

        tables =
          ex_files
          |> Enum.map(&Path.join(dir, &1))
          |> Enum.flat_map(fn path ->
            case read_file(path) do
              {:ok, table} -> [table]
              {:error, _} -> []
            end
          end)

        {:ok, tables}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def read_file(path) do
    with {:ok, source} <- File.read(path),
         {:ok, ast} <- Code.string_to_quoted(source) do
      parse_module_ast(ast)
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_module_ast({:defmodule, _meta, [module_name, [do: body]]}) do
    module_str = ast_to_module_string(module_name)

    case extract_schema_info(body) do
      {:ok, schema_name, schema_body} ->
        primary_key = extract_primary_key(body)
        columns = extract_columns(schema_body)
        has_timestamps = has_timestamps?(schema_body)
        has_timestamps = has_timestamps || has_timestamps?(body)

        table = %DBML.Ecto.SchemaReader{
          name: schema_name,
          module: module_str,
          primary_key: primary_key,
          columns: columns,
          has_timestamps: has_timestamps
        }

        {:ok, table}

      :error ->
        {:error, "File does not contain a schema definition"}
    end
  end

  defp parse_module_ast(_), do: {:error, "Not a module definition"}

  defp ast_to_module_string({:__aliases__, _meta, parts}) do
    parts |> Enum.map(&to_string/1) |> Enum.join(".")
  end

  defp ast_to_module_string(atom), do: to_string(atom)

  defp extract_schema_info({:__block__, _meta, statements}) do
    case Enum.find(statements, fn
      {:schema, _, [_name, _opts]} -> true
      _ -> false
    end) do
      {:schema, _meta, [name, [do: body]]} -> {:ok, name, body}
      _ -> :error
    end
  end

  defp extract_schema_info({:schema, _meta, [name, [do: body]]}) do
    {:ok, name, body}
  end

  defp extract_schema_info(_), do: :error

  defp extract_primary_key({:__block__, _meta, statements}) do
    case Enum.find(statements, fn
      {:@, _meta, [{:primary_key, _meta2, _args}]} -> true
      _ -> false
    end) do
      {:@, _meta, [{:primary_key, _meta2, [false]}]} ->
        :none

      {:@, _meta, [{:primary_key, _meta2, [{:__aliases__, _, _col_tuple} = col_spec]}]} ->
        extract_custom_pk(col_spec)

      {:@, _meta, [{:primary_key, _meta2, [col_spec]}]} when is_tuple(col_spec) ->
        extract_custom_pk(col_spec)

      _ ->
        :default
    end
  end

  defp extract_primary_key(_), do: :default

  defp extract_custom_pk({:{}, _meta, [col_name, type_atom, opts]}) when is_atom(col_name) and is_atom(type_atom) do
    autogenerate = is_list(opts) && Keyword.get(opts, :autogenerate, false)
    {:custom, to_string(col_name), type_atom, autogenerate}
  end

  defp extract_custom_pk({col_name, type_atom, opts}) when is_atom(col_name) and is_atom(type_atom) do
    autogenerate = is_list(opts) && Keyword.get(opts, :autogenerate, false)
    {:custom, to_string(col_name), type_atom, autogenerate}
  end

  defp extract_custom_pk(_), do: :default

  defp extract_columns({:__block__, _meta, statements}) do
    Enum.flat_map(statements, &extract_column_from_statement/1)
  end

  defp extract_columns(other) when is_list(other) do
    Enum.flat_map(other, &extract_column_from_statement/1)
  end

  defp extract_columns(tuple) when is_tuple(tuple) do
    [extract_column_from_statement(tuple)] |> List.flatten()
  end

  defp extract_column_from_statement({:field, _meta, [name, type | opts]}) when is_atom(name) do
    opts_kw = extract_opts(opts)
    col_name = to_string(name)
    col_type = ecto_type_to_dbml(type)

    is_enum = is_ecto_enum(type)
    enum_values = if is_enum, do: extract_enum_values(opts), else: []

    [
      %Column{
        name: col_name,
        type: col_type,
        is_enum: is_enum,
        enum_values: enum_values,
        null: Keyword.get(opts_kw, :null),
        unique: Keyword.get(opts_kw, :unique),
        default: Keyword.get(opts_kw, :default)
      }
    ]
  end

  defp extract_column_from_statement({:belongs_to, _meta, [assoc_name, module | opts]}) when is_atom(assoc_name) do
    opts_kw = extract_opts(opts)
    fk_col = Keyword.get(opts_kw, :foreign_key)
    fk_col_str = if fk_col, do: to_string(fk_col), else: "#{to_string(assoc_name)}_id"

    table_name = module_to_table_name(module)

    [
      %Column{
        name: fk_col_str,
        type: "int",
        is_fk: true,
        fk_table: table_name,
        fk_col: "id",
        null: Keyword.get(opts_kw, :null),
        unique: Keyword.get(opts_kw, :unique)
      }
    ]
  end

  defp extract_column_from_statement(:timestamps) do
    []
  end

  defp extract_column_from_statement(_), do: []

  defp extract_opts([{:__block__, _meta, _} | _rest]) do
    []
  end

  defp extract_opts([keyword_list | _rest]) when is_list(keyword_list) do
    keyword_list
  end

  defp extract_opts(_), do: []

  defp is_ecto_enum({:__aliases__, _meta, [:Ecto, :Enum]}), do: true
  defp is_ecto_enum(_), do: false

  defp extract_enum_values(opts) do
    opts_kw = extract_opts(opts)
    values = Keyword.get(opts_kw, :values, [])

    Enum.map(values, fn
      atom when is_atom(atom) -> to_string(atom)
      other -> to_string(other)
    end)
  end

  defp has_timestamps?({:__block__, _meta, statements}) do
    Enum.any?(statements, fn
      :timestamps -> true
      {:timestamps, _meta, []} -> true
      _ -> false
    end)
  end

  defp has_timestamps?(other) when is_list(other) do
    Enum.any?(other, fn
      :timestamps -> true
      {:timestamps, _meta, []} -> true
      _ -> false
    end)
  end

  defp has_timestamps?(_), do: false

  defp module_to_table_name({:__aliases__, _meta, parts}) do
    parts
    |> List.last()
    |> to_string()
    |> singularize()
    |> String.downcase()
    |> pluralize()
  end

  defp module_to_table_name(atom) when is_atom(atom) do
    atom
    |> to_string()
    |> singularize()
    |> String.downcase()
    |> pluralize()
  end

  defp module_to_table_name(str) when is_binary(str) do
    str
    |> singularize()
    |> String.downcase()
    |> pluralize()
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

  defp pluralize(name) do
    cond do
      String.ends_with?(name, "y") ->
        name |> String.trim_trailing("y") |> Kernel.<>("ies")

      String.ends_with?(name, "s") or String.ends_with?(name, "ch") or String.ends_with?(name, "sh") ->
        name <> "es"

      true ->
        name <> "s"
    end
  end

  defp ecto_type_to_dbml(type_atom) when is_atom(type_atom) do
    case type_atom do
      :integer -> "int"
      :string -> "varchar"
      :boolean -> "boolean"
      :float -> "float"
      :decimal -> "decimal"
      :date -> "date"
      :naive_datetime -> "timestamp"
      :datetime -> "timestamp"
      :utc_datetime -> "timestamp"
      :time -> "time"
      :uuid -> "uuid"
      :binary_id -> "uuid"
      :map -> "jsonb"
      _ -> "varchar"
    end
  end

  defp ecto_type_to_dbml(_), do: "varchar"
end
