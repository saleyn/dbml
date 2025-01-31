defmodule DBML.Utils do
  @moduledoc false

  def to_number([whole]) when is_integer(whole), do: whole
  def to_number(["-", whole]) when is_integer(whole), do: -whole

  def to_number([whole, decimal]) when is_integer(whole) do
    String.to_float(Integer.to_string(whole) <> "." <> decimal)
  end

  def to_number(["-", whole, decimal]) do
    -to_number([whole, decimal])
  end

  @doc """
  Remove the prefix based on the trailing "\n   ..." from a multiline string
  """
  def trim_multiline_string_prefix(iodata) do
    str = IO.iodata_to_binary(iodata)
    sfx =
      Regex.run(~r/(\n\s+)$/, str)
      |> Enum.at(1)
    if sfx do
      String.replace(str, sfx, "", global: false) |> String.replace(sfx, "\n")
    else
      str
    end
  end
end
