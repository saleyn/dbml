defmodule DBML.Ecto.DBMLWriterTest do
  use ExUnit.Case

  alias DBML.Ecto.{SchemaReader, DBMLWriter}

  describe "to_string/2" do
    test "renders a single table with standard primary key" do
      table = %SchemaReader{
        name: "users",
        module: "MyApp.User",
        primary_key: :default,
        columns: [
          %SchemaReader.Column{
            name: "id",
            type: "int",
            is_fk: false,
            null: nil,
            unique: nil,
            default: nil,
            is_enum: false,
            enum_values: []
          },
          %SchemaReader.Column{
            name: "email",
            type: "varchar",
            is_fk: false,
            null: false,
            unique: true,
            default: nil,
            is_enum: false,
            enum_values: []
          }
        ],
        has_timestamps: false
      }

      output = DBMLWriter.to_string([table])

      assert output =~ "table users {"
      assert output =~ "id int [pk]"
      assert output =~ "email varchar [not null, unique]"
    end

    test "renders a table with custom primary key" do
      table = %SchemaReader{
        name: "products",
        module: "MyApp.Product",
        primary_key: {:custom, "sku", :string, false},
        columns: [
          %SchemaReader.Column{
            name: "sku",
            type: "varchar",
            is_fk: false,
            null: false,
            unique: nil,
            default: nil,
            is_enum: false,
            enum_values: []
          }
        ],
        has_timestamps: false
      }

      output = DBMLWriter.to_string([table])

      assert output =~ "sku varchar [pk, not null]"
    end

    test "renders a table with autogenerate custom primary key" do
      table = %SchemaReader{
        name: "items",
        module: "MyApp.Item",
        primary_key: {:custom, "id", :binary_id, true},
        columns: [
          %SchemaReader.Column{
            name: "id",
            type: "uuid",
            is_fk: false,
            null: nil,
            unique: nil,
            default: nil,
            is_enum: false,
            enum_values: []
          }
        ],
        has_timestamps: false
      }

      output = DBMLWriter.to_string([table])

      assert output =~ "id uuid [pk, increment]"
    end

    test "renders enum fields correctly" do
      table = %SchemaReader{
        name: "blog_posts",
        module: "MyApp.BlogPost",
        primary_key: :default,
        columns: [
          %SchemaReader.Column{
            name: "id",
            type: "int",
            is_fk: false,
            null: nil,
            unique: nil,
            default: nil,
            is_enum: false,
            enum_values: []
          },
          %SchemaReader.Column{
            name: "status",
            type: "varchar",
            is_fk: false,
            null: nil,
            unique: nil,
            default: nil,
            is_enum: true,
            enum_values: ["draft", "published", "archived"]
          }
        ],
        has_timestamps: false
      }

      output = DBMLWriter.to_string([table])

      assert output =~ "enum status {"
      assert output =~ "draft"
      assert output =~ "published"
      assert output =~ "archived"
      assert output =~ "status status"
    end

    test "renders foreign key relationships" do
      user_table = %SchemaReader{
        name: "users",
        module: "MyApp.User",
        primary_key: :default,
        columns: [
          %SchemaReader.Column{
            name: "id",
            type: "int",
            is_fk: false,
            null: nil,
            unique: nil,
            default: nil,
            is_enum: false,
            enum_values: []
          }
        ],
        has_timestamps: false
      }

      post_table = %SchemaReader{
        name: "posts",
        module: "MyApp.Post",
        primary_key: :default,
        columns: [
          %SchemaReader.Column{
            name: "id",
            type: "int",
            is_fk: false,
            null: nil,
            unique: nil,
            default: nil,
            is_enum: false,
            enum_values: []
          },
          %SchemaReader.Column{
            name: "user_id",
            type: "int",
            is_fk: true,
            fk_table: "users",
            fk_col: "id",
            null: false,
            unique: nil,
            default: nil,
            is_enum: false,
            enum_values: []
          }
        ],
        has_timestamps: false
      }

      output = DBMLWriter.to_string([user_table, post_table])

      assert output =~ "ref: posts.user_id > users.id"
      assert output =~ "user_id int [not null, ref: > users.id]"
    end

    test "renders project block when project_name is provided" do
      table = %SchemaReader{
        name: "users",
        module: "MyApp.User",
        primary_key: :default,
        columns: [
          %SchemaReader.Column{
            name: "id",
            type: "int",
            is_fk: false,
            null: nil,
            unique: nil,
            default: nil,
            is_enum: false,
            enum_values: []
          }
        ],
        has_timestamps: false
      }

      output = DBMLWriter.to_string([table], project_name: "MyApp", database_type: "PostgreSQL")

      assert output =~ "project MyApp {"
      assert output =~ "database_type: \"PostgreSQL\""
    end

    test "sorts tables by foreign key dependencies" do
      # Users is referenced by posts, so should come first
      post_table = %SchemaReader{
        name: "posts",
        module: "MyApp.Post",
        primary_key: :default,
        columns: [
          %SchemaReader.Column{
            name: "id",
            type: "int",
            is_fk: false,
            null: nil,
            unique: nil,
            default: nil,
            is_enum: false,
            enum_values: []
          },
          %SchemaReader.Column{
            name: "user_id",
            type: "int",
            is_fk: true,
            fk_table: "users",
            fk_col: "id",
            null: nil,
            unique: nil,
            default: nil,
            is_enum: false,
            enum_values: []
          }
        ],
        has_timestamps: false
      }

      user_table = %SchemaReader{
        name: "users",
        module: "MyApp.User",
        primary_key: :default,
        columns: [
          %SchemaReader.Column{
            name: "id",
            type: "int",
            is_fk: false,
            null: nil,
            unique: nil,
            default: nil,
            is_enum: false,
            enum_values: []
          }
        ],
        has_timestamps: false
      }

      # Pass tables in reverse order
      output = DBMLWriter.to_string([post_table, user_table])

      # Users table should appear before posts table in output
      lines = String.split(output, "\n")
      user_line_idx = Enum.find_index(lines, &String.starts_with?(&1, "table users"))
      post_line_idx = Enum.find_index(lines, &String.starts_with?(&1, "table posts"))

      assert user_line_idx < post_line_idx
    end
  end

  describe "write/3" do
    test "writes DBML content to a file" do
      table = %SchemaReader{
        name: "users",
        module: "MyApp.User",
        primary_key: :default,
        columns: [
          %SchemaReader.Column{
            name: "id",
            type: "int",
            is_fk: false,
            null: nil,
            unique: nil,
            default: nil,
            is_enum: false,
            enum_values: []
          }
        ],
        has_timestamps: false
      }

      with_temp_file(fn path ->
        {:ok, output_path} = DBMLWriter.write([table], path)

        assert output_path == path
        {:ok, content} = File.read(path)
        assert content =~ "table users"
      end)
    end
  end

  describe "round-trip integration" do
    test "parse DBML -> generate schemas -> read schemas -> generate DBML" do
      # Original DBML
      dbml_input = """
      table users {
        id int [pk]
        email varchar [not null, unique]
        created_at timestamp
        updated_at timestamp
      }

      table posts {
        id int [pk]
        user_id int [not null]
        title varchar
        created_at timestamp
        updated_at timestamp
      }

      ref: posts.user_id > users.id
      """

      with_temp_dir(fn temp_dir ->
        # Parse DBML
        {:ok, tokens} = DBML.parse(dbml_input)

        # Generate Ecto schemas
        schema_dir = Path.join(temp_dir, "schemas")
        File.mkdir!(schema_dir)

        {:ok, _schema_paths} =
          DBML.generate_ecto_schemas(tokens, schema_dir,
            namespace: "MyApp",
            singularize: true
          )

        # Read generated schemas
        {:ok, tables} = SchemaReader.read_dir(schema_dir)

        # Generate DBML from schemas
        dbml_output = DBMLWriter.to_string(tables)

        # Parse both versions to compare structure
        {:ok, original_tokens} = DBML.parse(dbml_input)
        {:ok, roundtrip_tokens} = DBML.parse(dbml_output)

        # Check table names match
        original_tables = Keyword.get_values(original_tokens, :table)
        roundtrip_tables = Keyword.get_values(roundtrip_tokens, :table)

        assert length(original_tables) == length(roundtrip_tables)

        original_table_names =
          original_tables |> Enum.map(&(&1[:name])) |> Enum.sort()

        roundtrip_table_names =
          roundtrip_tables |> Enum.map(&(&1[:name])) |> Enum.sort()

        assert original_table_names == roundtrip_table_names
      end)
    end
  end

  # Helpers

  defp with_temp_file(fun) do
    temp_file = Path.join(System.tmp_dir!(), "test_#{:erlang.unique_integer()}.dbml")

    try do
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
