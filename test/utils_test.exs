defmodule DBML.UtilsTest do
  use ExUnit.Case, async: true
  import DBML.Utils

  test "trim_multiline_string_prefix" do
    assert "abc" = trim_multiline_string_prefix("abc")
    assert "abc\nefg\n" = trim_multiline_string_prefix("abc\n  efg\n  ")
    assert "abc\nefg\n" = trim_multiline_string_prefix("\n  abc\n  efg\n  ")
    assert "abc\nefg\n" = trim_multiline_string_prefix("\r\n  abc\r\n  efg\r\n  ")
  end

  test "unicode trim_multiline_string_prefix" do
    assert "тест\nabc\n✔️" = trim_multiline_string_prefix(["тест\n", "abc\n", "✔️"])
  end
end
