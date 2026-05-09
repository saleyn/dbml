defmodule DBML.Ecto.GeneratorTest do
  use ExUnit.Case, async: true

  setup do
    dir = Path.join(System.tmp_dir!(), "dbml_gen_test_#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, dir: dir}
  end

  test "generates file for each table", %{dir: dir} do
    {:ok, tokens} =
      DBML.parse("""
      table users { id int [pk] }
      table orders { id int [pk] }
      """)

    {:ok, paths} = DBML.Ecto.Generator.generate(tokens, dir, "MyApp")
    assert length(paths) == 2
    assert File.exists?(Path.join(dir, "users.ex"))
    assert File.exists?(Path.join(dir, "orders.ex"))
  end

  test "standard id PK with no special annotation", %{dir: dir} do
    {:ok, tokens} =
      DBML.parse("""
      table users {
        id int [pk]
        name varchar
      }
      """)

    {:ok, _paths} = DBML.Ecto.Generator.generate(tokens, dir, "MyApp")
    content = File.read!(Path.join(dir, "users.ex"))

    assert content =~ "defmodule MyApp.User do"
    assert content =~ "use Ecto.Schema"
    assert content =~ ~s(schema "users" do)
    assert content =~ "field :name, :string"
    refute String.contains?(content, "@primary_key")
  end

  test "custom non-standard PK with @primary_key annotation", %{dir: dir} do
    {:ok, tokens} =
      DBML.parse("""
      table property {
        property_id integer [pk]
        name varchar
      }
      """)

    {:ok, _paths} = DBML.Ecto.Generator.generate(tokens, dir, "MyApp")
    content = File.read!(Path.join(dir, "property.ex"))

    assert content =~ "defmodule MyApp.Property do"
    assert content =~ ~s(@primary_key {:property_id, :integer, autogenerate: false})
    assert content =~ "field :name, :string"
    refute String.contains?(content, "field :property_id")
  end

  test "autoincrement PK with @primary_key annotation", %{dir: dir} do
    {:ok, tokens} =
      DBML.parse("""
      table orders {
        order_id int [pk, increment]
        total int
      }
      """)

    {:ok, _paths} = DBML.Ecto.Generator.generate(tokens, dir, "MyApp")
    content = File.read!(Path.join(dir, "orders.ex"))

    assert content =~ ~s(@primary_key {:order_id, :integer, autogenerate: true})
  end

  test "timestamps() when both created_at and updated_at present", %{dir: dir} do
    {:ok, tokens} =
      DBML.parse("""
      table users {
        id int [pk]
        name varchar
        created_at timestamp
        updated_at timestamp
      }
      """)

    {:ok, _paths} = DBML.Ecto.Generator.generate(tokens, dir, "MyApp")
    content = File.read!(Path.join(dir, "users.ex"))

    assert content =~ "timestamps()"
    refute String.contains?(content, "field :created_at")
    refute String.contains?(content, "field :updated_at")
  end

  test "no timestamps when only created_at present", %{dir: dir} do
    {:ok, tokens} =
      DBML.parse("""
      table users {
        id int [pk]
        name varchar
        created_at timestamp
      }
      """)

    {:ok, _paths} = DBML.Ecto.Generator.generate(tokens, dir, "MyApp")
    content = File.read!(Path.join(dir, "users.ex"))

    refute String.contains?(content, "timestamps()")
    assert content =~ "field :created_at, :naive_datetime"
  end

  test "belongs_to with standalone ref (many_to_one)", %{dir: dir} do
    {:ok, tokens} =
      DBML.parse("""
      table users as U {
        id int [pk]
        name varchar
      }

      table orders {
        id int [pk]
        user_id int
      }

      ref: orders.user_id > U.id
      """)

    {:ok, _paths} = DBML.Ecto.Generator.generate(tokens, dir, "MyApp")
    content = File.read!(Path.join(dir, "orders.ex"))

    assert content =~ "belongs_to :user, MyApp.User, foreign_key: :user_id"
    refute String.contains?(content, "field :user_id")
  end

  test "belongs_to with inline ref", %{dir: dir} do
    {:ok, tokens} =
      DBML.parse("""
      table orders {
        id int [pk]
      }

      table order_items {
        id int [pk]
        order_id int [ref: > orders.id]
        quantity int
      }
      """)

    {:ok, _paths} = DBML.Ecto.Generator.generate(tokens, dir, "MyApp")
    content = File.read!(Path.join(dir, "order_items.ex"))

    assert content =~ "belongs_to :order, MyApp.Order, foreign_key: :order_id"
    refute String.contains?(content, "field :order_id")
  end

  test "alias resolution in refs", %{dir: dir} do
    {:ok, tokens} =
      DBML.parse("""
      table users as U {
        id int [pk]
      }

      table merchants {
        id int [pk]
        admin_id int [ref: > U.id]
      }
      """)

    {:ok, _paths} = DBML.Ecto.Generator.generate(tokens, dir, "MyApp")
    content = File.read!(Path.join(dir, "merchants.ex"))

    assert content =~ "belongs_to :user, MyApp.User, foreign_key: :admin_id"
  end

  test "enum type mapping", %{dir: dir} do
    {:ok, tokens} =
      DBML.parse("""
      enum product_status {
        out_of_stock
        in_stock
        running_low
      }

      table products {
        id int [pk]
        name varchar
        status product_status
      }
      """)

    {:ok, _paths} = DBML.Ecto.Generator.generate(tokens, dir, "MyApp")
    content = File.read!(Path.join(dir, "products.ex"))

    assert content =~ "field :status, Ecto.Enum, values: [:out_of_stock, :in_stock, :running_low]"
  end

  test "composite PK via index with @primary_key false", %{dir: dir} do
    {:ok, tokens} =
      DBML.parse("""
      table merchants {
        id int
        country_code int
        name varchar
        indexes {
          (id, country_code) [pk]
        }
      }
      """)

    {:ok, _paths} = DBML.Ecto.Generator.generate(tokens, dir, "MyApp")
    content = File.read!(Path.join(dir, "merchants.ex"))

    assert content =~ "@primary_key false"
    assert content =~ "field :id, :integer"
    assert content =~ "field :country_code, :integer"
    assert content =~ "field :name, :string"
  end

  test "no PK results in @primary_key false", %{dir: dir} do
    {:ok, tokens} =
      DBML.parse("""
      table logs {
        message varchar
      }
      """)

    {:ok, _paths} = DBML.Ecto.Generator.generate(tokens, dir, "MyApp")
    content = File.read!(Path.join(dir, "logs.ex"))

    assert content =~ "@primary_key false"
  end

  test "type mapping for all DBML types", %{dir: dir} do
    {:ok, tokens} =
      DBML.parse("""
      table types_test {
        id int [pk]
        int_col int
        varchar_col varchar
        bool_col boolean
        float_col float
        decimal_col decimal
        date_col date
        datetime_col datetime
        time_col time
        uuid_col uuid
        json_col json
        serial_col serial
      }
      """)

    {:ok, _paths} = DBML.Ecto.Generator.generate(tokens, dir, "MyApp")
    content = File.read!(Path.join(dir, "types_test.ex"))

    assert content =~ "field :int_col, :integer"
    assert content =~ "field :varchar_col, :string"
    assert content =~ "field :bool_col, :boolean"
    assert content =~ "field :float_col, :float"
    assert content =~ "field :decimal_col, :decimal"
    assert content =~ "field :date_col, :date"
    assert content =~ "field :datetime_col, :naive_datetime"
    assert content =~ "field :time_col, :time"
    assert content =~ "field :uuid_col, :binary_id"
    assert content =~ "field :json_col, :map"
    assert content =~ "field :serial_col, :integer"
  end

  test "column name with spaces sanitized to underscore", %{dir: dir} do
    {:ok, tokens} =
      DBML.parse("""
      table users {
        id int [pk]
        "full name" varchar
      }
      """)

    {:ok, _paths} = DBML.Ecto.Generator.generate(tokens, dir, "MyApp")
    content = File.read!(Path.join(dir, "users.ex"))

    assert content =~ "field :full_name, :string"
  end

  test "singularization of association names", %{dir: dir} do
    {:ok, tokens} =
      DBML.parse("""
      table countries {
        id int [pk]
      }

      table users {
        id int [pk]
        country_code int [ref: > countries.code]
      }

      table countries {
        code int [pk]
        name varchar
      }
      """)

    {:ok, _paths} = DBML.Ecto.Generator.generate(tokens, dir, "MyApp")
    content = File.read!(Path.join(dir, "users.ex"))

    assert content =~ "belongs_to :country, MyApp.Country, foreign_key: :country_code"
  end

  test "public API generate_ecto_schemas with explicit namespace", %{dir: dir} do
    {:ok, tokens} =
      DBML.parse("""
      table users {
        id int [pk]
      }
      """)

    {:ok, paths} = DBML.generate_ecto_schemas(tokens, dir, namespace: "CustomApp.Schema")
    content = File.read!(hd(paths))

    assert content =~ "defmodule CustomApp.Schema.User do"
  end

  test "public API generate_ecto_schemas defaults to project name", %{dir: dir} do
    {:ok, tokens} =
      DBML.parse("""
      project CMS {
        database_type: "PostgreSQL"
      }

      table users {
        id int [pk]
      }
      """)

    {:ok, paths} = DBML.generate_ecto_schemas(tokens, dir)
    content = File.read!(hd(paths))

    assert content =~ "defmodule CMS.User do"
  end

  test "public API generate_ecto_schemas with no namespace and no project", %{dir: dir} do
    {:ok, tokens} =
      DBML.parse("""
      table users {
        id int [pk]
      }
      """)

    {:ok, paths} = DBML.generate_ecto_schemas(tokens, dir)
    content = File.read!(hd(paths))

    assert content =~ "defmodule .User do"
  end

  test "one_to_many ref on column stays as plain field", %{dir: dir} do
    {:ok, tokens} =
      DBML.parse("""
      table users {
        id int [pk]
        name varchar
      }

      table posts {
        id int [pk]
        user_id int
      }

      ref: users.id < posts.user_id
      """)

    {:ok, _paths} = DBML.Ecto.Generator.generate(tokens, dir, "MyApp")
    users_content = File.read!(Path.join(dir, "users.ex"))

    refute String.contains?(users_content, "belongs_to")
    assert users_content =~ "field :name, :string"
  end

  test "singularize option set to false keeps plural table names", %{dir: dir} do
    {:ok, tokens} =
      DBML.parse("""
      table users {
        id int [pk]
        name varchar
      }

      table order_items {
        id int [pk]
        quantity int
      }
      """)

    {:ok, paths} = DBML.generate_ecto_schemas(tokens, dir, namespace: "MyApp", singularize: false)
    users_content = File.read!(Enum.at(paths, 0))
    items_content = File.read!(Enum.at(paths, 1))

    assert users_content =~ "defmodule MyApp.Users do"
    assert items_content =~ "defmodule MyApp.OrderItems do"
  end

  test "singularize option defaults to true", %{dir: dir} do
    {:ok, tokens} =
      DBML.parse("""
      table products {
        id int [pk]
      }
      """)

    {:ok, paths} = DBML.generate_ecto_schemas(tokens, dir, namespace: "MyApp")
    content = File.read!(hd(paths))

    assert content =~ "defmodule MyApp.Product do"
  end

  test "singularize false with belongs_to still singularizes association names", %{dir: dir} do
    {:ok, tokens} =
      DBML.parse("""
      table users {
        id int [pk]
      }

      table orders {
        id int [pk]
        user_id int [ref: > users.id]
      }
      """)

    {:ok, paths} = DBML.generate_ecto_schemas(tokens, dir, namespace: "MyApp", singularize: false)
    orders_content = File.read!(Enum.at(paths, 1))

    assert orders_content =~ "defmodule MyApp.Orders do"
    assert orders_content =~ "belongs_to :users, MyApp.Users, foreign_key: :user_id"
  end

  test "serialization produces valid Elixir syntax", %{dir: dir} do
    {:ok, tokens} =
      DBML.parse("""
      project MyDB {
        database_type: "PostgreSQL"
      }

      table users {
        id int [pk]
        email varchar [not null, unique]
        created_at timestamp
        updated_at timestamp
      }

      table orders {
        id int [pk]
        user_id int [ref: > users.id]
        total int
      }
      """)

    {:ok, paths} = DBML.generate_ecto_schemas(tokens, dir)

    Enum.each(paths, fn path ->
      content = File.read!(path)
      assert content =~ "defmodule"
      assert content =~ "use Ecto.Schema"
      assert content =~ "schema"
      assert content =~ "end"
    end)
  end

  # New tests for :update option

  test "error when file exists and update is false (default)", %{dir: dir} do
    {:ok, tokens} =
      DBML.parse("""
      table users {
        id int [pk]
        name varchar
      }
      """)

    # Create the file first
    File.write!(Path.join(dir, "users.ex"), "old content")

    # Try to generate without update flag (default update: false)
    result = DBML.Ecto.Generator.generate(tokens, dir, "MyApp")

    # Should get an error, not overwrite
    assert match?({:error, "File already exists: " <> _}, result)

    # Verify the existing file was not modified
    content = File.read!(Path.join(dir, "users.ex"))
    assert content == "old content"
  end

  test "error when file exists and update is explicitly false", %{dir: dir} do
    {:ok, tokens} =
      DBML.parse("""
      table products {
        id int [pk]
      }
      """)

    # Create the file first
    File.write!(Path.join(dir, "products.ex"), "old content")

    # Try to generate with update: false explicitly
    result = DBML.Ecto.Generator.generate(tokens, dir, "MyApp", true, false)

    # Should get an error
    assert match?({:error, "File already exists: " <> _}, result)

    # Verify the existing file was not modified
    content = File.read!(Path.join(dir, "products.ex"))
    assert content == "old content"
  end

  test "update: true overwrites existing file", %{dir: dir} do
    {:ok, tokens} =
      DBML.parse("""
      table users {
        id int [pk]
        name varchar
      }
      """)

    # Create the file with old content
    File.write!(Path.join(dir, "users.ex"), "old content")

    # Generate with update: true
    {:ok, paths} = DBML.Ecto.Generator.generate(tokens, dir, "MyApp", true, true)

    # Should succeed and return paths
    assert length(paths) == 1
    assert File.exists?(Path.join(dir, "users.ex"))

    # Verify the file was overwritten with new content
    content = File.read!(Path.join(dir, "users.ex"))
    assert content =~ "defmodule MyApp.User do"
    refute content == "old content"
  end

  test "update: true creates files if they don't exist", %{dir: dir} do
    {:ok, tokens} =
      DBML.parse("""
      table orders {
        id int [pk]
        total int
      }
      """)

    # Generate with update: true but no pre-existing files
    {:ok, paths} = DBML.Ecto.Generator.generate(tokens, dir, "MyApp", true, true)

    # Should succeed and create the file
    assert length(paths) == 1
    assert File.exists?(Path.join(dir, "orders.ex"))

    content = File.read!(Path.join(dir, "orders.ex"))
    assert content =~ "defmodule MyApp.Order do"
  end

  test "public API with update: true", %{dir: dir} do
    {:ok, tokens} =
      DBML.parse("""
      table users {
        id int [pk]
        email varchar
      }
      """)

    # Create the file with old content
    File.write!(Path.join(dir, "users.ex"), "old content")

    # Generate via public API with update: true
    {:ok, paths} = DBML.generate_ecto_schemas(tokens, dir, namespace: "MyApp", update: true)

    # Should succeed
    assert length(paths) == 1

    # Verify the file was overwritten
    content = File.read!(Path.join(dir, "users.ex"))
    assert content =~ "defmodule MyApp.User do"
    refute content == "old content"
  end

  test "public API error when file exists and update is false (default)", %{dir: dir} do
    {:ok, tokens} =
      DBML.parse("""
      table products {
        id int [pk]
      }
      """)

    # Create the file first
    File.write!(Path.join(dir, "products.ex"), "old content")

    # Try via public API with default update: false
    result = DBML.generate_ecto_schemas(tokens, dir, namespace: "MyApp")

    # Should get an error
    assert match?({:error, "File already exists: " <> _}, result)

    # Verify the file was not modified
    content = File.read!(Path.join(dir, "products.ex"))
    assert content == "old content"
  end
end
