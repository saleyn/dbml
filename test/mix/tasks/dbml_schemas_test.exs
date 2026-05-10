defmodule Mix.Tasks.Dbml.SchemasTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureIO

  setup do
    dir = Path.join(System.tmp_dir!(), "mix_dbml_schemas_#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, dir: dir}
  end

  test "run with valid arguments generates schemas", %{dir: dir} do
    dbml_file = Path.join(dir, "schema.dbml")
    File.write!(dbml_file, "table users { id int [pk] }")
    output_dir = Path.join(dir, "schemas")
    File.mkdir_p!(output_dir)

    output = capture_io(fn ->
      Mix.Tasks.Dbml.Schemas.run([dbml_file, "-o", output_dir])
    end)

    assert output =~ "Generated:"
    assert File.exists?(Path.join(output_dir, "users.ex"))
  end

  test "run with namespace option", %{dir: dir} do
    dbml_file = Path.join(dir, "schema.dbml")
    File.write!(dbml_file, "table products { id int [pk] }")
    output_dir = Path.join(dir, "schemas")
    File.mkdir_p!(output_dir)

    capture_io(fn ->
      Mix.Tasks.Dbml.Schemas.run([dbml_file, "-o", output_dir, "-n", "MyApp.Schema"])
    end)

    content = File.read!(Path.join(output_dir, "products.ex"))
    assert content =~ "defmodule MyApp.Schema.Product do"
  end

  test "run with help flag" do
    output = capture_io(fn ->
      Mix.Tasks.Dbml.Schemas.run(["--help"])
    end)

    assert output =~ "Generate Ecto schemas"
  end

  test "run with missing output-dir raises" do
    assert_raise Mix.Error, fn ->
      capture_io(fn ->
        Mix.Tasks.Dbml.Schemas.run(["schema.dbml"])
      end)
    end
  end

  test "run with nonexistent file raises" do
    assert_raise Mix.Error, fn ->
      capture_io(fn ->
        Mix.Tasks.Dbml.Schemas.run(["nonexistent.dbml", "-o", "/tmp"])
      end)
    end
  end

  test "run with update option overwrites existing files", %{dir: dir} do
    dbml_file = Path.join(dir, "schema.dbml")
    File.write!(dbml_file, "table users { id int [pk] }")
    output_dir = Path.join(dir, "schemas")
    File.mkdir_p!(output_dir)
    File.write!(Path.join(output_dir, "users.ex"), "old content")

    output = capture_io(fn ->
      Mix.Tasks.Dbml.Schemas.run([dbml_file, "-o", output_dir, "--update"])
    end)

    assert output =~ "Generated:"
    content = File.read!(Path.join(output_dir, "users.ex"))
    assert content =~ "defmodule"
    refute content == "old content"
  end

  test "run with long option names" do
    assert_raise Mix.Error, fn ->
      capture_io(fn ->
        Mix.Tasks.Dbml.Schemas.run(["--output-dir"])
      end)
    end
  end
end
