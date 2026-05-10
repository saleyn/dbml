defmodule Mix.Tasks.Dbml.MigrationsTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureIO

  setup do
    dir = Path.join(System.tmp_dir!(), "mix_dbml_migrations_#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, dir: dir}
  end

  test "run with valid arguments generates migrations", %{dir: dir} do
    dbml_file = Path.join(dir, "schema.dbml")
    File.write!(dbml_file, "table users { id int [pk] }")
    output_dir = Path.join(dir, "migrations")
    File.mkdir_p!(output_dir)

    output = capture_io(fn ->
      Mix.Tasks.Dbml.Migrations.run([dbml_file, "-o", output_dir, "-r", "MyApp.Repo"])
    end)

    assert output =~ "Generated:"
    assert Enum.any?(File.ls!(output_dir), fn f -> String.ends_with?(f, "_create_users.exs") end)
  end

  test "run generates valid migration files", %{dir: dir} do
    dbml_file = Path.join(dir, "schema.dbml")
    File.write!(dbml_file, """
    table users {
      id int [pk]
      email varchar
      name varchar
    }
    """)
    output_dir = Path.join(dir, "migrations")
    File.mkdir_p!(output_dir)

    capture_io(fn ->
      Mix.Tasks.Dbml.Migrations.run([dbml_file, "-o", output_dir, "-r", "MyApp.Repo"])
    end)

    [migration_file] = File.ls!(output_dir)
    content = File.read!(Path.join(output_dir, migration_file))

    assert content =~ "defmodule"
    assert content =~ "def change do"
    assert content =~ "create table"
  end

  test "run with help flag" do
    output = capture_io(fn ->
      Mix.Tasks.Dbml.Migrations.run(["--help"])
    end)

    assert output =~ "Generate Ecto migrations"
  end

  test "run with missing output-dir raises" do
    assert_raise Mix.Error, fn ->
      capture_io(fn ->
        Mix.Tasks.Dbml.Migrations.run(["schema.dbml", "-r", "MyApp.Repo"])
      end)
    end
  end

  test "run with missing repo raises" do
    assert_raise Mix.Error, fn ->
      capture_io(fn ->
        Mix.Tasks.Dbml.Migrations.run(["schema.dbml", "-o", "/tmp"])
      end)
    end
  end

  test "run with nonexistent file raises" do
    assert_raise Mix.Error, fn ->
      capture_io(fn ->
        Mix.Tasks.Dbml.Migrations.run(["nonexistent.dbml", "-o", "/tmp", "-r", "Repo"])
      end)
    end
  end

  test "run with update option", %{dir: dir} do
    dbml_file = Path.join(dir, "schema.dbml")
    File.write!(dbml_file, "table orders { id int [pk] }")
    output_dir = Path.join(dir, "migrations")
    File.mkdir_p!(output_dir)

    output = capture_io(fn ->
      Mix.Tasks.Dbml.Migrations.run([dbml_file, "-o", output_dir, "-r", "MyApp.Repo", "--update"])
    end)

    assert output =~ "Generated:"
  end

  test "run with multiple tables generates multiple migrations", %{dir: dir} do
    dbml_file = Path.join(dir, "schema.dbml")
    File.write!(dbml_file, """
    table users {
      id int [pk]
      name varchar
    }

    table orders {
      id int [pk]
      user_id int
    }
    """)
    output_dir = Path.join(dir, "migrations")
    File.mkdir_p!(output_dir)

    capture_io(fn ->
      Mix.Tasks.Dbml.Migrations.run([dbml_file, "-o", output_dir, "-r", "MyApp.Repo"])
    end)

    files = File.ls!(output_dir)
    assert length(files) == 2
  end

  test "run with short repo alias -r" do
    assert_raise Mix.Error, fn ->
      capture_io(fn ->
        Mix.Tasks.Dbml.Migrations.run(["nonexistent.dbml", "-o", "/tmp", "-r", "Repo"])
      end)
    end
  end
end
