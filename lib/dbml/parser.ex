defmodule DBML.Parser.Helper do
  import NimbleParsec

  def keyword(<<c, rest::binary>> = keyword) when c in ?a..?z do
    choice([string(keyword), string(<<c-32, rest::binary>>)])
  end

  def find_and_ignore_keyword(keyword) do
    lookahead(keyword(keyword))
    |> ignore(keyword(keyword))
  end
end

defmodule DBML.Parser do
  @moduledoc false
  import NimbleParsec
  import DBML.Parser.Helper

  @space_characters [?\s]
  @newline_characters [?\r, ?\n]
  @whitespace_characters @space_characters ++ @newline_characters

  # Misc.
  required_spaces = ignore(ascii_string(@space_characters, min: 1))
  optional_spaces = ignore(ascii_string(@space_characters, min: 0))

  required_whitespaces = ignore(ascii_string(@whitespace_characters, min: 1))
  optional_whitespaces = ignore(ascii_string(@whitespace_characters, min: 0))

  single_line_comment =
    lookahead(string("//"))
    |> ignore(string("//"))
    |> ascii_string([not: ?\n], min: 1)

  multi_line_comment =
    lookahead(string("/*"))
    |> ignore(string("/*"))
    |> repeat(
      lookahead_not(string("*/"))
      |> utf8_char([])
      |> ignore()
    )
    |> ignore(string("*/"))

  comment = choice([single_line_comment, multi_line_comment])

  misc = ignore(choice([comment, required_whitespaces]))

  single_quoted_string =
    ignore(string("'"))
    |> utf8_string([not: ?'], min: 1)
    |> ignore(string("'"))

  double_quoted_string =
    ignore(string("\""))
    |> utf8_string([not: ?"], min: 1)
    |> ignore(string("\""))

  multiline_string =
    ignore(string("'''"))
    |> repeat(
      lookahead_not(string("'''"))
      |> utf8_char([])
    )
    |> ignore(string("'''"))
    |> reduce({DBML.Utils, :trim_multiline_string_prefix, []})

  quoted_string = choice([double_quoted_string, single_quoted_string, multiline_string])

  number =
    optional(string("-"))
    |> integer(min: 1)
    |> optional(
      ignore(string("."))
      |> ascii_string([?0..?9], min: 1)
    )
    |> reduce({DBML.Utils, :to_number, []})

  boolean = choice([replace(string("true"), true), replace(string("false"), false)])
  null = replace(string("null"), nil)

  expression =
    lookahead(string("`"))
    |> ignore(string("`"))
    |> ascii_string([not: ?`], min: 1)
    |> ignore(string("`"))
    |> unwrap_and_tag(:expression)

  identifier =
    choice([
      quoted_string,
      ascii_string([?0..?9, ?A..?Z, ?a..?z, ?_], min: 1)
    ])

  defcombinatorp(
    :primary_key,
    choice([string("pk"), string("primary key")]) |> replace(true) |> unwrap_and_tag(:primary)
  )

  color =
    ascii_char([?#])
    |> ascii_string([?0..?9, ?A..?Z, ?a..?z], min: 3, max: 8)
    |> reduce({:string, :uppercase, []})
    |> reduce({:to_string, []})

  setting =
    utf8_string([?0..?9, ?A..?Z, ?a..?z, ?_], min: 1)
    |> ignore(ascii_char([?:]))
    |> reduce({DBML.Utils, :maybe_atom, []})
    |> ignore(misc)
    |> choice([
      quoted_string,
      color
    ])
    |> optional(ignore(string(",")))
    |> reduce({List, :to_tuple, []})

  settings =
    ignore(string("["))
    |> repeat(choice([setting, misc]))
    |> ignore(string("]"))
    |> reduce({:maps, :from_list, []})
    |> unwrap_and_tag(:settings)
    |> ignore(misc)

  # Matches optional "[note: 'some any-quoted note']"
  defcombinatorp(
    :optional_settings,
    optional(
      ignore(optional_spaces)
      |> concat(settings)
    )
    |> repeat(misc)
  )

  note_definition =
    lookahead(string("Note"))
    |> ignore(string("Note"))
    |> repeat(misc)
    |> choice([
      lookahead(string("{"))
      |> ignore(string("{"))
      |> repeat(misc)
      |> concat(quoted_string)
      |> repeat(misc)
      |> ignore(string("}")),
      ignore(string(":")) |> repeat(misc) |> concat(quoted_string)
    ])

  project_definitions =
    ignore(string("{"))
    |> repeat(
      choice([
        misc,
        note_definition |> unwrap_and_tag(:note),
        unwrap_and_tag(identifier, :key)
        |> ignore(string(":"))
        |> ignore(misc)
        |> unwrap_and_tag(quoted_string, :value)
        |> tag(:meta)
      ])
    )
    |> ignore(string("}"))

  project =
    find_and_ignore_keyword("project")
    |> ignore(required_spaces)
    |> unwrap_and_tag(identifier, :name)
    |> repeat(misc)
    |> tag(project_definitions, :definitions)

  # Tables

  column_type =
    choice([
      quoted_string,
      ascii_string([not: ?\s, not: ?\n, not: ?{, not: ?}], min: 1)
    ])

  ref_column =
    unwrap_and_tag(identifier, :table)
    |> ignore(string("."))
    |> unwrap_and_tag(identifier, :column)
    |> reduce({:maps, :from_list, []})

  default_choices = choice([quoted_string, number, boolean, expression, null])

  ref_type =
    choice([
      string(">") |> replace(:many_to_one),
      string("<") |> replace(:one_to_many),
      string("-") |> replace(:one_to_one)
    ])

  column_ref =
    lookahead(string("ref:"))
    |> ignore(string("ref:"))
    |> concat(optional_whitespaces)
    |> unwrap_and_tag(ref_type, :type)
    |> concat(optional_spaces)
    |> unwrap_and_tag(ref_column, :related)
    |> reduce({:maps, :from_list, []})

  column_setting =
    choice([
      ignore(string("default:"))
      |> repeat(misc)
      |> concat(default_choices)
      |> unwrap_and_tag(:default),
      parsec(:primary_key),
      ignore(string("increment")) |> replace(true) |> unwrap_and_tag(:autoincrement),
      ignore(string("unique")) |> replace(true) |> unwrap_and_tag(:unique),
      ignore(string("null")) |> replace(true) |> unwrap_and_tag(:null),
      ignore(string("not null")) |> replace(false) |> unwrap_and_tag(:null),
      ignore(string("note:")) |> repeat(misc) |> concat(quoted_string) |> unwrap_and_tag(:note),
      unwrap_and_tag(column_ref, :reference)
    ])

  column_settings =
    ignore(string("["))
    |> repeat(misc)
    |> concat(column_setting)
    |> repeat(
      choice([
        misc,
        ignore(string(","))
        |> repeat(misc)
        |> concat(column_setting)
      ])
    )
    |> ignore(string("]"))

  column_definition =
    unwrap_and_tag(identifier, :name)
    |> ignore(required_spaces)
    |> unwrap_and_tag(column_type, :type)
    |> optional(
      ignore(optional_spaces)
      |> concat(column_settings)
    )
    |> reduce({:maps, :from_list, []})

  index_setting =
    choice([
      misc,
      parsec(:primary_key),
      string("unique") |> replace(true) |> unwrap_and_tag(:unique),
      ignore(string("type:"))
      |> repeat(misc)
      |> choice([string("hash"), string("btree")])
      |> unwrap_and_tag(:type),
      ignore(string("name:")) |> repeat(misc) |> concat(identifier) |> unwrap_and_tag(:name),
      ignore(string("note:")) |> repeat(misc) |> concat(quoted_string) |> unwrap_and_tag(:note)
    ])

  index_settings =
    lookahead(string("["))
    |> ignore(string("["))
    |> concat(index_setting)
    |> optional(
      repeat(
        choice([
          misc,
          lookahead(string(","))
          |> ignore(string(","))
          |> repeat(misc)
          |> concat(index_setting)
        ])
      )
    )
    |> ignore(string("]"))

  single_column_index =
    tag(identifier, :columns)
    |> ignore(optional_spaces)
    |> concat(optional(index_settings))
    |> reduce({:maps, :from_list, []})

  composite_index =
    lookahead(string("("))
    |> ignore(string("("))
    |> ignore(optional_spaces)
    |> choice([expression, identifier])
    |> repeat(
      choice([
        misc,
        lookahead(string(","))
        |> ignore(string(","))
        |> repeat(misc)
        |> choice([expression, identifier])
      ])
    )
    |> ignore(string(")"))
    |> tag(:columns)
    |> ignore(optional_spaces)
    |> concat(optional(index_settings))
    |> reduce({:maps, :from_list, []})

  index_definition = choice([composite_index, single_column_index])

  indexes =
    lookahead(string("indexes"))
    |> ignore(string("indexes"))
    |> repeat(misc)
    |> ignore(string("{"))
    |> repeat(choice([misc, index_definition]))
    |> ignore(string("}"))
    |> wrap()

  table =
    find_and_ignore_keyword("table")
    |> ignore(required_spaces)
    |> unwrap_and_tag(identifier, :name)
    |> optional(
      required_spaces
      |> ignore(string("as"))
      |> concat(required_spaces)
      |> concat(identifier)
      |> unwrap_and_tag(:alias)
    )
    |> ignore(repeat(misc))
    |> parsec(:optional_settings)
    # |> reduce(table_definitions, {:maps, :from_list, []})
    |> ignore(string("{"))
    |> concat(
      repeat(
        choice([
          misc,
          column_definition
        ])
      )
      |> tag(:fields)
    )
    |> repeat(
      choice([
        misc,
        unwrap_and_tag(note_definition, :note),
        unwrap_and_tag(indexes, :indexes)
      ])
    )
    |> ignore(string("}"))
    |> reduce({:maps, :from_list, []})

  # Table groups
  table_group =
    lookahead(string("TableGroup"))
    |> ignore(string("TableGroup"))
    |> repeat(misc)
    |> unwrap_and_tag(identifier, :name)
    |> repeat(misc)
    |> parsec(:optional_settings)
    |> tag(
      ignore(string("{"))
      |> repeat(choice([misc, identifier]))
      |> ignore(string("}")),
      :tables
    )
    |> reduce({:maps, :from_list, []})

  # Define enum value parser
  enum_value =
    unwrap_and_tag(identifier, :value)
    |> parsec(:optional_settings)
    |> repeat(misc)

  # Define enum parser with comma-separated values
  enum =
    lookahead(string("enum"))
    |> ignore(string("enum"))
    |> ignore(misc)
    # Enum name
    |> unwrap_and_tag(identifier, :name)
    |> ignore(misc)
    |> ignore(string("{"))
    |> ignore(optional(misc))
    |> tag(
      reduce(enum_value, {:maps, :from_list, []})
      |> optional(
        repeat(reduce(enum_value, {:maps, :from_list, []}))
      )
      |> ignore(optional(misc)),
      :items
    )
    |> ignore(string("}"))
    |> reduce({:maps, :from_list, []})

  # References
  ref_short_form =
    lookahead(string(":"))
    |> ignore(string(":"))
    |> repeat(misc)
    |> unwrap_and_tag(ref_column, :owner)
    |> repeat(misc)
    |> unwrap_and_tag(ref_type, :type)
    |> concat(optional_spaces)
    |> unwrap_and_tag(ref_column, :related)

  ref_long_form =
    repeat(misc)
    |> ignore(string("{"))
    |> repeat(misc)
    |> unwrap_and_tag(ref_column, :owner)
    |> repeat(misc)
    |> unwrap_and_tag(ref_type, :type)
    |> concat(optional_spaces)
    |> unwrap_and_tag(ref_column, :related)
    |> repeat(misc)
    |> ignore(string("}"))

  ref =
    lookahead(string("Ref"))
    |> ignore(string("Ref"))
    |> optional(
      ignore(required_spaces)
      |> tag(identifier, :name)
    )
    |> choice([ref_short_form, ref_long_form])
    |> reduce({:maps, :from_list, []})

  parser =
    repeat(
      choice([
        ignore(misc),
        tag(project, :project),
        unwrap_and_tag(table, :table),
        unwrap_and_tag(table_group, :table_group),
        unwrap_and_tag(enum, :enum),
        tag(ref, :ref)
      ])
    )
    |> repeat(misc)

  # defparsec(:project, project)
  # defparsec(:table, table)
  # defparsec(:table_group, table_group)
  defparsec(:enum, enum)
  # defparsec(:ref, ref)
  defparsec(:parse, parser)
end
