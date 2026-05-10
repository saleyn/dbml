defmodule Mix.Tasks.Dbml.FileTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureIO

  setup do
    dir = Path.join(System.tmp_dir!(), "mix_dbml_file_#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, dir: dir}
  end

  test "run with valid arguments generates DBML file", %{dir: dir} do
    schemas_dir = Path.join(dir, "schemas")
    File.mkdir_p!(schemas_dir)

    schema_content = """
    defmodule MyApp.User do
      use Ecto.Schema

      schema "users" do
        field :name, :string
      end
    end
    """

    File.write!(Path.join(schemas_dir, "user.ex"), schema_content)
    output_file = Path.join(dir, "output.dbml")

    output = capture_io(fn ->
      Mix.Tasks.Dbml.File.run([schemas_dir, "-o", output_file])
    end)

    assert output =~ "Generated:"
    assert File.exists?(output_file)
  end

  test "run generates valid DBML content", %{dir: dir} do
    schemas_dir = Path.join(dir, "schemas")
    File.mkdir_p!(schemas_dir)

    schema_content = """
    defmodule MyApp.User do
      use Ecto.Schema

      schema "users" do
        field :name, :string
        field :email, :string
      end
    end
    """

    File.write!(Path.join(schemas_dir, "user.ex"), schema_content)
    output_file = Path.join(dir, "output.dbml")

    capture_io(fn ->
      Mix.Tasks.Dbml.File.run([schemas_dir, "-o", output_file])
    end)

    content = File.read!(output_file)
    assert content =~ "table"
    assert content =~ "users"
  end

  test "run with help flag" do
    output = capture_io(fn ->
      Mix.Tasks.Dbml.File.run(["--help"])
    end)

    assert output =~ "Generate DBML"
  end

  test "run with missing output option raises" do
    assert_raise Mix.Error, fn ->
      capture_io(fn ->
        Mix.Tasks.Dbml.File.run(["/tmp"])
      end)
    end
  end

  test "run with nonexistent directory raises" do
    assert_raise Mix.Error, fn ->
      capture_io(fn ->
        Mix.Tasks.Dbml.File.run(["nonexistent_dir", "-o", "output.dbml"])
      end)
    end
  end

  test "run with project name option", %{dir: dir} do
    schemas_dir = Path.join(dir, "schemas")
    File.mkdir_p!(schemas_dir)

    schema_content = """
    defmodule MyApp.User do
      use Ecto.Schema
      schema "users" do
        field :name, :string
      end
    end
    """

    File.write!(Path.join(schemas_dir, "user.ex"), schema_content)
    output_file = Path.join(dir, "output.dbml")

    capture_io(fn ->
      Mix.Tasks.Dbml.File.run([schemas_dir, "-o", output_file, "--project-name", "TestProject"])
    end)

    content = File.read!(output_file)
    assert content =~ "project TestProject"
  end

  test "run with database type option", %{dir: dir} do
    schemas_dir = Path.join(dir, "schemas")
    File.mkdir_p!(schemas_dir)

    schema_content = """
    defmodule MyApp.User do
      use Ecto.Schema
      schema "users" do
        field :name, :string
      end
    end
    """

    File.write!(Path.join(schemas_dir, "user.ex"), schema_content)
    output_file = Path.join(dir, "output.dbml")

    capture_io(fn ->
      Mix.Tasks.Dbml.File.run([schemas_dir, "-o", output_file, "--database-type", "MySQL"])
    end)

    content = File.read!(output_file)
    # Should generate DBML regardless of the database type passed
    assert content =~ "table"
  end

  test "run with short output alias -o" do
    assert_raise Mix.Error, fn ->
      capture_io(fn ->
        Mix.Tasks.Dbml.File.run(["nonexistent", "-o", "out.dbml"])
      end)
    end
  end

  test "run with multiple schema files", %{dir: dir} do
    schemas_dir = Path.join(dir, "schemas")
    File.mkdir_p!(schemas_dir)

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
      end
    end
    """

    File.write!(Path.join(schemas_dir, "user.ex"), user_schema)
    File.write!(Path.join(schemas_dir, "post.ex"), post_schema)
    output_file = Path.join(dir, "output.dbml")

    capture_io(fn ->
      Mix.Tasks.Dbml.File.run([schemas_dir, "-o", output_file])
    end)

    content = File.read!(output_file)
    assert content =~ "users"
    assert content =~ "posts"
  end
end
