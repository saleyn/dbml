defmodule DBML.Ecto.MigrationGeneratorTest do
  use ExUnit.Case, async: true

  setup do
    dir = Path.join(System.tmp_dir!(), "dbml_mig_test_#{:erlang.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, dir: dir}
  end

  test "generates one file per table with correct timestamps", %{dir: dir} do
    {:ok, tokens} = DBML.parse("""
      table users { id int [pk] }
      table orders { id int [pk] }
    """)

    paths = DBML.Ecto.MigrationGenerator.generate(tokens, dir, "MyApp.Repo")
    assert length(paths) == 2

    assert Enum.any?(paths, &String.contains?(&1, "20000101000001_create_users.exs"))
    assert Enum.any?(paths, &String.contains?(&1, "20000101000002_create_orders.exs"))
  end

  test "uses custom base_timestamp", %{dir: dir} do
    {:ok, tokens} = DBML.parse("""
      table users { id int [pk] }
    """)

    paths = DBML.Ecto.MigrationGenerator.generate(tokens, dir, "MyApp.Repo", base_timestamp: 20_250_101_000_000)
    assert Enum.any?(paths, &String.contains?(&1, "20250101000001_create_users.exs"))
  end

  test "standard id PK is skipped in migration", %{dir: dir} do
    {:ok, tokens} = DBML.parse("""
      table users {
        id int [pk]
        name varchar
      }
    """)

    DBML.Ecto.MigrationGenerator.generate(tokens, dir, "MyApp.Repo")
    content = File.read!(Path.join(dir, "20000101000001_create_users.exs"))

    assert content =~ "defmodule MyApp.Repo.Migrations.CreateUsers do"
    assert content =~ "use Ecto.Migration"
    assert content =~ "create table(:users) do"
    assert content =~ "add :name, :string"
    refute String.contains?(content, "add :id")
    refute String.contains?(content, "primary_key: false")
  end

  test "custom non-standard PK", %{dir: dir} do
    {:ok, tokens} = DBML.parse("""
      table orders {
        order_id int [pk]
        total int
      }
    """)

    DBML.Ecto.MigrationGenerator.generate(tokens, dir, "MyApp.Repo")
    content = File.read!(Path.join(dir, "20000101000001_create_orders.exs"))

    assert content =~ "create table(:orders, primary_key: false) do"
    assert content =~ "add :total, :integer"
  end

  test "autoincrement PK", %{dir: dir} do
    {:ok, tokens} = DBML.parse("""
      table products {
        product_id int [pk, increment]
        name varchar
      }
    """)

    DBML.Ecto.MigrationGenerator.generate(tokens, dir, "MyApp.Repo")
    content = File.read!(Path.join(dir, "20000101000001_create_products.exs"))

    assert content =~ "create table(:products, primary_key: false) do"
    assert content =~ "add :name, :string"
  end

  test "timestamps() when both created_at and updated_at present", %{dir: dir} do
    {:ok, tokens} = DBML.parse("""
      table users {
        id int [pk]
        name varchar
        created_at timestamp
        updated_at timestamp
      }
    """)

    DBML.Ecto.MigrationGenerator.generate(tokens, dir, "MyApp.Repo")
    content = File.read!(Path.join(dir, "20000101000001_create_users.exs"))

    assert content =~ "timestamps()"
    refute String.contains?(content, "add :created_at")
    refute String.contains?(content, "add :updated_at")
  end

  test "no timestamps() when only created_at present", %{dir: dir} do
    {:ok, tokens} = DBML.parse("""
      table users {
        id int [pk]
        name varchar
        created_at timestamp
      }
    """)

    DBML.Ecto.MigrationGenerator.generate(tokens, dir, "MyApp.Repo")
    content = File.read!(Path.join(dir, "20000101000001_create_users.exs"))

    refute String.contains?(content, "timestamps()")
    assert content =~ "add :created_at, :datetime"
  end

  test "not null constraint", %{dir: dir} do
    {:ok, tokens} = DBML.parse("""
      table users {
        id int [pk]
        email varchar [not null]
      }
    """)

    DBML.Ecto.MigrationGenerator.generate(tokens, dir, "MyApp.Repo")
    content = File.read!(Path.join(dir, "20000101000001_create_users.exs"))

    assert content =~ "add :email, :string, null: false"
  end

  test "unique constraint", %{dir: dir} do
    {:ok, tokens} = DBML.parse("""
      table users {
        id int [pk]
        email varchar [unique]
      }
    """)

    DBML.Ecto.MigrationGenerator.generate(tokens, dir, "MyApp.Repo")
    content = File.read!(Path.join(dir, "20000101000001_create_users.exs"))

    assert content =~ "add :email, :string, unique: true"
  end

  test "default value as literal", %{dir: dir} do
    {:ok, tokens} = DBML.parse("""
      table orders {
        id int [pk]
        status varchar [default: 'pending']
        quantity int [default: 1]
      }
    """)

    DBML.Ecto.MigrationGenerator.generate(tokens, dir, "MyApp.Repo")
    content = File.read!(Path.join(dir, "20000101000001_create_orders.exs"))

    assert content =~ "add :status, :string, default: \"pending\""
    assert content =~ "add :quantity, :integer, default: 1"
  end

  test "default value as expression", %{dir: dir} do
    {:ok, tokens} = DBML.parse("""
      table products {
        id int [pk]
        created_at datetime [default: `now()`]
      }
    """)

    DBML.Ecto.MigrationGenerator.generate(tokens, dir, "MyApp.Repo")
    content = File.read!(Path.join(dir, "20000101000001_create_products.exs"))

    assert content =~ "add :created_at, :datetime, default: fragment(\"now()\")"
  end

  test "foreign key reference as inline", %{dir: dir} do
    {:ok, tokens} = DBML.parse("""
      table countries {
        code int [pk]
        name varchar
      }

      table users {
        id int [pk]
        country_code int [ref: > countries.code]
      }
    """)

    paths = DBML.Ecto.MigrationGenerator.generate(tokens, dir, "MyApp.Repo")

    # countries should come before users
    countries_idx = Enum.find_index(paths, &String.contains?(&1, "create_countries"))
    users_idx = Enum.find_index(paths, &String.contains?(&1, "create_users"))
    assert countries_idx < users_idx

    content = File.read!(Path.join(dir, "20000101000002_create_users.exs"))

    assert content =~ "add :country_code, references(:countries, column: :code)"
  end

  test "foreign key reference as standalone", %{dir: dir} do
    {:ok, tokens} = DBML.parse("""
      table orders {
        id int [pk]
        user_id int
      }

      table users {
        id int [pk]
        name varchar
      }

      ref: orders.user_id > users.id
    """)

    paths = DBML.Ecto.MigrationGenerator.generate(tokens, dir, "MyApp.Repo")

    # users should come before orders
    users_idx = Enum.find_index(paths, &String.contains?(&1, "create_users"))
    orders_idx = Enum.find_index(paths, &String.contains?(&1, "create_orders"))
    assert users_idx < orders_idx

    content = File.read!(Path.join(dir, "20000101000002_create_orders.exs"))

    assert content =~ "add :user_id, references(:users, column: :id)"
  end

  test "FK index is created", %{dir: dir} do
    {:ok, tokens} = DBML.parse("""
      table users {
        id int [pk]
        name varchar
      }

      table orders {
        id int [pk]
        user_id int [ref: > users.id]
      }
    """)

    DBML.Ecto.MigrationGenerator.generate(tokens, dir, "MyApp.Repo")
    content = File.read!(Path.join(dir, "20000101000002_create_orders.exs"))

    assert content =~ "create index(:orders, [:user_id])"
  end

  test "unique index from indexes block", %{dir: dir} do
    {:ok, tokens} = DBML.parse("""
      table users {
        id int [pk]
        email varchar

        indexes {
          email [unique]
        }
      }
    """)

    DBML.Ecto.MigrationGenerator.generate(tokens, dir, "MyApp.Repo")
    content = File.read!(Path.join(dir, "20000101000001_create_users.exs"))

    assert content =~ "create unique_index(:users, [:email])"
  end

  test "composite index from indexes block", %{dir: dir} do
    {:ok, tokens} = DBML.parse("""
      table order_items {
        order_id int
        product_id int
        quantity int

        indexes {
          (order_id, product_id)
        }
      }
    """)

    DBML.Ecto.MigrationGenerator.generate(tokens, dir, "MyApp.Repo")
    content = File.read!(Path.join(dir, "20000101000001_create_order_items.exs"))

    assert content =~ "create index(:order_items, [:order_id, :product_id])"
  end

  test "type mapping", %{dir: dir} do
    {:ok, tokens} = DBML.parse("""
      table products {
        id int [pk]
        name varchar
        description text
        price decimal
        quantity integer
        in_stock boolean
        rating float
        release_date date
        published_at datetime
        metadata json
      }
    """)

    DBML.Ecto.MigrationGenerator.generate(tokens, dir, "MyApp.Repo")
    content = File.read!(Path.join(dir, "20000101000001_create_products.exs"))

    assert content =~ "add :name, :string"
    assert content =~ "add :description, :string"
    assert content =~ "add :price, :decimal"
    assert content =~ "add :quantity, :integer"
    assert content =~ "add :in_stock, :boolean"
    assert content =~ "add :rating, :float"
    assert content =~ "add :release_date, :date"
    assert content =~ "add :published_at, :datetime"
    assert content =~ "add :metadata, :map"
  end

  test "composite PK via indexes block", %{dir: dir} do
    {:ok, tokens} = DBML.parse("""
      table merchant_periods {
        merchant_id int
        period_id int
        start_date datetime

        indexes {
          (merchant_id, period_id) [pk]
        }
      }
    """)

    DBML.Ecto.MigrationGenerator.generate(tokens, dir, "MyApp.Repo")
    content = File.read!(Path.join(dir, "20000101000001_create_merchant_periods.exs"))

    assert content =~ "create table(:merchant_periods, primary_key: false) do"
    assert content =~ "add :merchant_id, :integer"
    assert content =~ "add :period_id, :integer"
  end

  test "table with spaces in name", %{dir: dir} do
    {:ok, tokens} = DBML.parse("""
      table "user accounts" {
        id int [pk]
        name varchar
      }
    """)

    paths = DBML.Ecto.MigrationGenerator.generate(tokens, dir, "MyApp.Repo")

    assert Enum.any?(paths, &String.contains?(&1, "create_user_accounts"))

    content = File.read!(hd(paths))

    assert content =~ "create table(:user_accounts) do"
    assert content =~ "defmodule MyApp.Repo.Migrations.CreateUserAccounts do"
  end

  test "topological sort orders tables by dependencies", %{dir: dir} do
    {:ok, tokens} = DBML.parse("""
      table merchants {
        id int [pk]
        country_code int [ref: > countries.code]
      }

      table countries {
        code int [pk]
        name varchar
      }

      table order_items {
        id int [pk]
        order_id int [ref: > orders.id]
        product_id int [ref: > products.id]
      }

      table orders {
        id int [pk]
        merchant_id int [ref: > merchants.id]
      }

      table products {
        id int [pk]
        merchant_id int [ref: > merchants.id]
      }
    """)

    paths = DBML.Ecto.MigrationGenerator.generate(tokens, dir, "MyApp.Repo")

    # Extract order from filenames
    path_order = Enum.map(paths, &Path.basename/1) |> Enum.sort()

    # countries must be first (no deps)
    assert Enum.at(path_order, 0) =~ "countries"

    # merchants depends on countries, so comes after
    merchants_idx = Enum.find_index(path_order, &String.contains?(&1, "merchants"))
    countries_idx = Enum.find_index(path_order, &String.contains?(&1, "countries"))
    assert countries_idx < merchants_idx

    # orders depends on merchants, so comes after
    orders_idx = Enum.find_index(path_order, &String.contains?(&1, "create_orders"))
    assert merchants_idx < orders_idx

    # order_items depends on both orders and products
    order_items_idx = Enum.find_index(path_order, &String.contains?(&1, "order_items"))
    assert orders_idx < order_items_idx
    products_idx = Enum.find_index(path_order, &String.contains?(&1, "products"))
    assert products_idx < order_items_idx
  end

  test "multiple column constraints", %{dir: dir} do
    {:ok, tokens} = DBML.parse("""
      table users {
        id int [pk]
        email varchar [not null, unique]
        age int [default: 18]
      }
    """)

    DBML.Ecto.MigrationGenerator.generate(tokens, dir, "MyApp.Repo")
    content = File.read!(Path.join(dir, "20000101000001_create_users.exs"))

    assert content =~ "add :email, :string, null: false, unique: true"
    assert content =~ "add :age, :integer, default: 18"
  end
end
