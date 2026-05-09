defmodule DBML.Ecto.SchemaReaderTest do
  use ExUnit.Case

  alias DBML.Ecto.SchemaReader

  describe "read_file/1" do
    test "reads a schema with standard id primary key" do
      schema = """
      defmodule MyApp.User do
        use Ecto.Schema

        schema "users" do
          field :email, :string
          field :name, :string
        end
      end
      """

      with_temp_file(schema, fn path ->
        {:ok, table} = SchemaReader.read_file(path)

        assert table.name == "users"
        assert table.module == "MyApp.User"
        assert table.primary_key == :default
        assert length(table.columns) == 2

        email_col = Enum.find(table.columns, &(&1.name == "email"))
        assert email_col.type == "varchar"
        assert email_col.is_fk == false

        name_col = Enum.find(table.columns, &(&1.name == "name"))
        assert name_col.type == "varchar"
      end)
    end

    test "reads a schema with @primary_key false" do
      schema = """
      defmodule MyApp.Order do
        use Ecto.Schema

        @primary_key false
        schema "orders" do
          field :code, :string
        end
      end
      """

      with_temp_file(schema, fn path ->
        {:ok, table} = SchemaReader.read_file(path)

        assert table.name == "orders"
        assert table.primary_key == :none
      end)
    end

    test "reads a schema with custom primary key" do
      schema = """
      defmodule MyApp.Product do
        use Ecto.Schema

        @primary_key {:sku, :string, autogenerate: false}
        schema "products" do
          field :name, :string
        end
      end
      """

      with_temp_file(schema, fn path ->
        {:ok, table} = SchemaReader.read_file(path)

        assert table.name == "products"
        assert table.primary_key == {:custom, "sku", :string, false}
      end)
    end

    test "reads a schema with autogenerate custom primary key" do
      schema = """
      defmodule MyApp.Item do
        use Ecto.Schema

        @primary_key {:id, :binary_id, autogenerate: true}
        schema "items" do
          field :title, :string
        end
      end
      """

      with_temp_file(schema, fn path ->
        {:ok, table} = SchemaReader.read_file(path)

        assert table.primary_key == {:custom, "id", :binary_id, true}
      end)
    end

    test "reads a schema with belongs_to association" do
      schema = """
      defmodule MyApp.Post do
        use Ecto.Schema

        schema "posts" do
          field :title, :string
          belongs_to :user, MyApp.User
        end
      end
      """

      with_temp_file(schema, fn path ->
        {:ok, table} = SchemaReader.read_file(path)

        fk_col = Enum.find(table.columns, &(&1.name == "user_id"))
        assert fk_col.is_fk == true
        assert fk_col.fk_table == "users"
        assert fk_col.fk_col == "id"
        assert fk_col.type == "int"
      end)
    end

    test "reads a schema with custom foreign_key option" do
      schema = """
      defmodule MyApp.Comment do
        use Ecto.Schema

        schema "comments" do
          field :text, :string
          belongs_to :author, MyApp.User, foreign_key: :author_id
        end
      end
      """

      with_temp_file(schema, fn path ->
        {:ok, table} = SchemaReader.read_file(path)

        fk_col = Enum.find(table.columns, &(&1.name == "author_id"))
        assert fk_col.is_fk == true
        assert fk_col.fk_table == "users"
      end)
    end

    test "reads a schema with Ecto.Enum field" do
      schema = """
      defmodule MyApp.BlogPost do
        use Ecto.Schema

        schema "blog_posts" do
          field :title, :string
          field :status, Ecto.Enum, values: [:draft, :published, :archived]
        end
      end
      """

      with_temp_file(schema, fn path ->
        {:ok, table} = SchemaReader.read_file(path)

        status_col = Enum.find(table.columns, &(&1.name == "status"))
        assert status_col.is_enum == true
        assert status_col.enum_values == ["draft", "published", "archived"]
      end)
    end

    test "reads a schema with timestamps" do
      schema = """
      defmodule MyApp.Article do
        use Ecto.Schema

        schema "articles" do
          field :title, :string
          timestamps()
        end
      end
      """

      with_temp_file(schema, fn path ->
        {:ok, table} = SchemaReader.read_file(path)

        assert table.has_timestamps == true
      end)
    end

    test "reads a schema with field constraints" do
      schema = """
      defmodule MyApp.Account do
        use Ecto.Schema

        schema "accounts" do
          field :email, :string, null: false, unique: true
          field :name, :string, default: "Unknown"
        end
      end
      """

      with_temp_file(schema, fn path ->
        {:ok, table} = SchemaReader.read_file(path)

        email_col = Enum.find(table.columns, &(&1.name == "email"))
        assert email_col.null == false
        assert email_col.unique == true

        name_col = Enum.find(table.columns, &(&1.name == "name"))
        assert name_col.default == "Unknown"
      end)
    end

    test "handles various Ecto types" do
      schema = """
      defmodule MyApp.Mixed do
        use Ecto.Schema

        schema "mixed" do
          field :age, :integer
          field :price, :decimal
          field :active, :boolean
          field :ratio, :float
          field :birthday, :date
          field :created, :datetime
          field :uid, :binary_id
          field :data, :map
          field :duration, :time
        end
      end
      """

      with_temp_file(schema, fn path ->
        {:ok, table} = SchemaReader.read_file(path)

        type_map = Enum.into(table.columns, %{}, &{&1.name, &1.type})

        assert type_map["age"] == "int"
        assert type_map["price"] == "decimal"
        assert type_map["active"] == "boolean"
        assert type_map["ratio"] == "float"
        assert type_map["birthday"] == "date"
        assert type_map["created"] == "timestamp"
        assert type_map["uid"] == "uuid"
        assert type_map["data"] == "jsonb"
        assert type_map["duration"] == "time"
      end)
    end

    test "returns error for file without schema definition" do
      schema = """
      defmodule MyApp.Helper do
        def some_function do
          :ok
        end
      end
      """

      with_temp_file(schema, fn path ->
        {:error, _reason} = SchemaReader.read_file(path)
      end)
    end

    test "returns error for non-module definition" do
      code = "some_function = fn -> :ok end"

      with_temp_file(code, fn path ->
        {:error, _reason} = SchemaReader.read_file(path)
      end)
    end
  end

  describe "read_dir/1" do
    test "reads all schema files from a directory" do
      user_schema = """
      defmodule MyApp.User do
        use Ecto.Schema
        schema "users" do
          field :name, :string
        end
      end
      """

      post_schema = """
      defmodule MyApp.Post do
        use Ecto.Schema
        schema "posts" do
          field :title, :string
          belongs_to :user, MyApp.User
        end
      end
      """

      with_temp_dir(fn dir ->
        File.write!(Path.join(dir, "user.ex"), user_schema)
        File.write!(Path.join(dir, "post.ex"), post_schema)

        {:ok, tables} = SchemaReader.read_dir(dir)

        assert length(tables) == 2
        assert Enum.map(tables, & &1.name) |> Enum.sort() == ["posts", "users"]
      end)
    end

    test "skips non-schema files" do
      schema = """
      defmodule MyApp.User do
        use Ecto.Schema
        schema "users" do
          field :name, :string
        end
      end
      """

      helper = """
      defmodule MyApp.Helper do
        def some_function do
          :ok
        end
      end
      """

      with_temp_dir(fn dir ->
        File.write!(Path.join(dir, "user.ex"), schema)
        File.write!(Path.join(dir, "helper.ex"), helper)

        {:ok, tables} = SchemaReader.read_dir(dir)

        assert length(tables) == 1
        assert hd(tables).name == "users"
      end)
    end

    test "returns error for non-existent directory" do
      {:error, _reason} = SchemaReader.read_dir("/non/existent/path")
    end
  end

  # Helpers

  defp with_temp_file(content, fun) do
    temp_file = Path.join(System.tmp_dir!(), "test_#{:erlang.unique_integer()}.ex")

    try do
      File.write!(temp_file, content)
      fun.(temp_file)
    after
      File.rm!(temp_file)
    end
  end

  defp with_temp_dir(fun) do
    temp_dir = Path.join(System.tmp_dir!(), "test_#{:erlang.unique_integer()}")
    File.mkdir!(temp_dir)

    try do
      fun.(temp_dir)
    after
      File.rm_rf!(temp_dir)
    end
  end
end
