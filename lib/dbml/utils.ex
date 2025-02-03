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

  def maybe_atom([str]), do: maybe_atom(str)
  def maybe_atom(str) do
    (str in ["note", "color"]) && String.to_atom(str) || str
  end

  @doc """
  Remove the prefix based on the trailing "\r?\n   ..." from a multiline string
  """
  def trim_multiline_string_prefix(iodata) do
    str = IO.chardata_to_string(iodata)

    case Regex.run(~r/(\r?\n\s+)$/, str) do
      [_, sfx] ->
        str = String.starts_with?(str, sfx) && String.replace(str, sfx, "", global: false) || str
        String.replace(str, sfx, "\n")
      nil ->
        str
    end
  end
end
