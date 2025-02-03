defmodule DBML.ParserTest do
  use ExUnit.Case, async: true
  doctest DBML

  describe "parse/1" do
    test "parse string" do
      assert {:ok, tokens} =
               DBML.parse("""
               project CMS {
                 database_type: "PostgreSQL"
                 note: 'CMS database'
               }

               //// -- LEVEL 1
               //// -- tables and references

               // Creating tables
               Table users as U {
                 id int [pk, increment]
                 full_name varchar
                 created_at timestamp
                 country_code int
               }

               Table countries {
                 code int [pk]
                 name varchar
                 continent_name varchar
                }

               // Creating references
               // You can also define relaionship separately
               // > many-to-one; < one-to-many; - one-to-one
               Ref: U.country_code > countries.code
               Ref: merchants.country_code > countries.code

               //----------------------------------------------//

               //// -- LEVEL 2
               //// -- Adding column settings

               Table order_items {
                 order_id int [ref: > orders.id] // inline relationship (many-to-one)
                 product_id int
                 quantity int [default: 1] // default value
               }

               Ref: order_items.product_id > products.id

               Table orders {
                 id int [pk] // primary key
                 user_id int [not null, unique]
                 status varchar
                 created_at varchar [note: 'When order created'] // add column note
               }

               //----------------------------------------------//

               //// -- Level 3
               //// -- Enum, indexes

               // Enum for 'products' table below
               enum products_status {
                 out_of_stock
                 in_stock
                 running_low [note: 'less than 20'] // add column note
               }

               // indexes: You can define a single or multi-column index
               table products {
                 id int [pk]
                 name varchar
                 merchant_id int [not null]
                 price int
                 status products_status
                 created_at datetime [default: `now()`]

                 indexes {
                   (merchant_id, status) [name: "product_status"]
                   id [unique]
                 }

                 Note {
                   'asdfasd'
                 }
               }

               table merchants {
                 id int
                 country_code int
                 merchant_name varchar

                 "created at" varchar
                 admin_id int [ref: > U.id]
                 indexes {
                   (id, country_code) [pk]
                 }
               }

               table merchant_periods {
                 id int [pk]
                 merchant_id int
                 country_code int
                 start_date datetime
                 end_date datetime
               }

               Ref: products.merchant_id > merchants.id // many-to-one
               """)

      assert tokens != []
      assert "CMS" == get_in(tokens, [:project, :name])
      assert "users" == get_in(tokens, [:table, :name])
      assert 4 == get_in(tokens, [:table, :fields]) |> length()
    end

    test "parse file" do
      assert {:ok,
              [
                table: %{
                  name: "property",
                  fields: [
                    %{
                      name: "unit_id",
                      type: "integer",
                      primary: true,
                      reference: %{
                        type: :many_to_one,
                        related: %{table: "unit", column: "unit_id"}
                      }
                    },
                    %{name: "property_id", type: "integer", primary: true},
                    %{name: "name", type: "varchar", null: false},
                    %{name: "url", type: "varchar"},
                    %{name: "created_at", type: "timestamp", null: false},
                    %{name: "updated_at", type: "timestamp"}
                  ],
                  note: "  Defines a unit of measure,\n  which is a multi-line string\n",
                  indexes: [%{name: "idx_property_name", columns: ["name"], unique: true}]
                },
                table: %{name: "user1", fields: [%{name: "f1", type: "string"}], settings: %{}},
                table: %{name: "user2", fields: [%{name: "f1", type: "string"}], settings: %{note: "User table"}},
                table: %{name: "user3", fields: [%{name: "f1", type: "string"}], settings: %{color: "#123AAA", note: "User table"}}
              ]} =
               DBML.parse_file("test/data/table.dbml")
    end

    test "parses an enum" do
      assert {:ok,
              [
                enum: %{
                  name: "user_role",
                  items: [%{value: "admin"}, %{value: "user"}, %{value: "guest"}]
                }
              ]} =
               DBML.parse("""
               enum user_role {
                 admin
                 user
                 guest
               }
               """)
    end

    test "parses an enum from file" do
      assert {
        :ok,
        [
          enum: %{
            items: [
              %{value: "abc", settings: %{note: "Test1"}},
              %{value: "efg", settings: %{note: "Test2"}},
              %{value: "hij"},
              %{value: "klm"}
            ],
            name: "color"
          }
        ]
      } = DBML.parse_file("test/data/enum.dbml")
    end

    test "parses miscellaneous tables" do
      assert {:ok, tokens} = DBML.parse_file("test/data/misc.dbml")
      assert 2 == Enum.count(tokens, fn({k,_}) -> k == :table end)
    end

    test "ignore multi-line comment" do
      assert {:ok,
              [
                enum: %{name: "abc", items: [%{value: "a"}, %{value: "b"}]}
              ]} =
               DBML.parse("""
                /* This
                is
                a multiline
                comment
                */ enum abc { a b }
                """)
    end


  end
end
