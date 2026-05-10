# DBML — Elixir Parser and Code Generator

[![build](https://github.com/saleyn/dbml/actions/workflows/ci.yaml/badge.svg)](https://github.com/saleyn/dbml/actions/workflows/ci.yaml)
[![Hex.pm](https://img.shields.io/hexpm/v/dbml.svg)](https://hex.pm/packages/dbml)
[![Hex.pm](https://img.shields.io/hexpm/dt/dbml.svg)](https://hex.pm/packages/dbml)

A complete Elixir implementation for parsing [Database Markup Language (DBML)](https://dbml.dbdiagram.io/) schemas and generating Ecto schema files and Ecto migrations automatically.

**Features:**
- Full DBML syntax parser using NimbleParsec
- Generate Ecto schema files from DBML definitions
- Generate Ecto migration files with intelligent change detection
- Generate DBML from existing Ecto schema files (reverse operation)
- Incremental updates: only regenerate changed schemas and migrations
- Type mapping, relationships (belongs_to), enums, indexes, constraints
- Zero-friction integration with Phoenix/Ecto projects
- **CLI tools:** Standalone `dbml` escript and Mix tasks for command-line usage

## Table of Contents

- [Installation](#installation)
- [Quick Start](#quick-start)
- [CLI Usage (Escript & Mix Tasks)](#cli-usage-escript--mix-tasks)
- [Parsing DBML](#parsing-dbml)
- [Generating Ecto Schemas](#generating-ecto-schemas)
- [Generating Ecto Migrations](#generating-ecto-migrations)
- [Generating DBML from Ecto Schemas](#generating-dbml-from-ecto-schemas)
- [Type Mapping](#type-mapping)
- [Examples](#examples)
- [API Reference](#api-reference)

---

## Installation

Add `dbml` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:dbml, "~> 0.3"}
  ]
end
```

Then run:

```bash
mix deps.get
```

---

## Quick Start

### Parse a DBML file

```elixir
{:ok, tokens} = DBML.parse_file("schema.dbml")
```

### Generate Ecto schemas

```elixir
{:ok, tokens} = DBML.parse_file("schema.dbml")

DBML.generate_ecto_schemas(tokens, "lib/my_app/schema", namespace: "MyApp.Schema")
# Output: lib/my_app/schema/users.ex, lib/my_app/schema/posts.ex, ...
```

### Generate Ecto migrations

```elixir
DBML.generate_ecto_migrations(
  tokens,
  "priv/repo/migrations",
  "MyApp.Repo"
)
# Output: priv/repo/migrations/20000101000001_create_users.exs, ...
```

---

## CLI Usage (Escript & Mix Tasks)

The DBML library includes both a standalone escript binary and Mix tasks for convenient command-line usage.

### Building the escript

```bash
mix escript.build
# Produces: ./dbml (standalone executable)
```

### Using the `dbml` escript

```bash
# Generate Ecto schemas from DBML
./dbml schemas schema.dbml -o lib/my_app/schema --namespace MyApp.Schema

# Generate Ecto migrations from DBML
./dbml migrations schema.dbml -o priv/repo/migrations -r MyApp.Repo

# Generate DBML from existing Ecto schemas
./dbml file lib/my_app/schema -o schema.dbml --project-name MyApp

# Show help
./dbml help
./dbml schemas --help
./dbml migrations --help
./dbml file --help
```

### Using Mix tasks

The same functionality is available as Mix tasks for use during development:

```bash
# Generate Ecto schemas from DBML
mix dbml.schemas schema.dbml -o lib/my_app/schema --namespace MyApp.Schema

# Generate Ecto migrations from DBML
mix dbml.migrations schema.dbml -o priv/repo/migrations -r MyApp.Repo

# Generate DBML from existing Ecto schemas
mix dbml.file lib/my_app/schema -o schema.dbml --project-name MyApp

# Show help for each task
mix help dbml.schemas
mix help dbml.migrations
mix help dbml.file
```

### Escript options

#### `dbml schemas <DBML_FILE> [OPTIONS]`

Generate Ecto schema files from a DBML schema.

```
-o, --output-dir DIR         Output directory for .ex files (required)
-n, --namespace MODULE       Module namespace prefix (optional)
--singularize true|false     Singularize table names (default: true)
--update true|false          Allow overwriting existing files (default: false)
```

#### `dbml migrations <DBML_FILE> [OPTIONS]`

Generate Ecto migration files from a DBML schema.

```
-o, --output-dir DIR         Output directory for migration files (required)
-r, --repo MODULE            Repo module name (required)
--base-timestamp TIMESTAMP   Base timestamp for migrations (default: 20000101000000)
--update true|false          Allow incremental updates (default: false)
```

#### `dbml file <SCHEMAS_DIR> [OPTIONS]`

Generate a DBML file from existing Ecto schema files (reverse operation).

```
-o, --output FILE            Output path for the .dbml file (required)
--project-name NAME          Project name for DBML header (optional)
--database-type TYPE         Database type (default: PostgreSQL)
```

---

## Parsing DBML

### Parse from string

```elixir
dbml_string = """
table users {
  id int [pk]
  email varchar [unique, not null]
  created_at timestamp
}
"""

{:ok, tokens} = DBML.parse(dbml_string)
```

### Parse from file

```elixir
{:ok, tokens} = DBML.parse_file("schema.dbml")
```

### Error handling

```elixir
case DBML.parse(invalid_dbml) do
  {:ok, tokens} -> process_tokens(tokens)
  {:error, reason} -> handle_error(reason)
end
```

---

## Generating Ecto Schemas

### Basic usage

```elixir
{:ok, tokens} = DBML.parse_file("schema.dbml")

# Generate with default namespace (extracted from DBML project name, or empty)
{:ok, paths} = DBML.generate_ecto_schemas(tokens, "lib/my_app/schema")

# Generate with explicit namespace
{:ok, paths} = DBML.generate_ecto_schemas(
  tokens,
  "lib/my_app/schema",
  namespace: "MyApp.Schema"
)
```

### Options

#### `:namespace` (string, optional)

Module namespace prefix for generated schemas.

**Default:** Extracted from DBML `project { name: "..." }`, or empty string `""`.

```elixir
{:ok, paths} = DBML.generate_ecto_schemas(
  tokens,
  "lib/my_app/schema",
  namespace: "MyApp.Schema"
)
# Generates: MyApp.Schema.User, MyApp.Schema.Post, etc.
```

#### `:singularize` (boolean, default: `true`)

Convert plural table names to singular module names.

```elixir
# With singularize: true (default)
# Table: users → Module: User
# Table: posts → Module: Post

# With singularize: false
{:ok, paths} = DBML.generate_ecto_schemas(
  tokens,
  "lib/my_app/schema",
  singularize: false
)
# Table: users → Module: Users
# Table: posts → Module: Posts
```

#### `:update` (boolean, default: `false`)

Control behavior when schema files already exist.

```elixir
# update: false (default) — error if any file exists
{:error, "File already exists: lib/my_app/schema/users.ex"} =
  DBML.generate_ecto_schemas(tokens, "lib/my_app/schema")

# update: true — overwrite existing files
{:ok, paths} = DBML.generate_ecto_schemas(
  tokens,
  "lib/my_app/schema",
  update: true
)
```

### Return value

- **Success:** `{:ok, ["/path/to/users.ex", "/path/to/posts.ex", ...]}`
- **Error:** `{:error, "File already exists: /path/to/file.ex"}` (when `update: false`)

### Generated schema features

The generator creates full Ecto schemas with:

- **Primary keys:** standard `id`, custom PKs, composite PKs, autoincrement
- **Relationships:** `belongs_to` for foreign keys, alias resolution
- **Timestamps:** automatic `timestamps()` when both `created_at` and `updated_at` present
- **Types:** full mapping of DBML types to Ecto types
- **Enums:** Ecto.Enum fields for DBML enums
- **Constraints:** `null: false`, `unique: true` in field definitions

---

## Generating Ecto Migrations

### Basic usage

```elixir
{:ok, tokens} = DBML.parse_file("schema.dbml")

# Generate migrations
{:ok, paths} = DBML.generate_ecto_migrations(
  tokens,
  "priv/repo/migrations",
  "MyApp.Repo"
)
```

### Options

#### `:base_timestamp` (integer, default: `20000101000000`)

Base timestamp for migration file naming. Each table gets `base + index`.

```elixir
{:ok, paths} = DBML.generate_ecto_migrations(
  tokens,
  "priv/repo/migrations",
  "MyApp.Repo",
  base_timestamp: 20_250_101_000_000
)
# Generates: 20250101000001_create_users.exs, 20250101000002_create_posts.exs, ...
```

#### `:update` (boolean, default: `false`)

Control incremental migration generation when schemas change.

**`update: false` (default):**
- Returns error if any migration file exists
- No files are written

```elixir
{:error, "File already exists: priv/repo/migrations/20000101000001_create_users.exs"} =
  DBML.generate_ecto_migrations(tokens, "priv/repo/migrations", "MyApp.Repo")
```

**`update: true`:**
- Detects existing migration files
- Compares generated content with existing migrations
- **Unchanged tables:** skipped (no new file)
- **Changed tables:** creates new migration with fresh timestamp (old file untouched)
- **New tables:** creates migration at appropriate timestamp

```elixir
# First generation
{:ok, ["/priv/repo/migrations/20000101000001_create_users.exs"]} =
  DBML.generate_ecto_migrations(tokens, "priv/repo/migrations", "MyApp.Repo", update: true)

# Schema updated: add email column to users, add posts table
{:ok, paths} =
  DBML.generate_ecto_migrations(new_tokens, "priv/repo/migrations", "MyApp.Repo", update: true)

# Returns: [
#   "/priv/repo/migrations/20000101000002_create_users.exs",    # changed (new migration)
#   "/priv/repo/migrations/20000101000002_create_posts.exs"     # new table
# ]

# Old migration still exists:
# /priv/repo/migrations/20000101000001_create_users.exs (unchanged)
```

### Return value

- **Success:** `{:ok, ["/path/to/20000101000001_create_users.exs", ...]}`
- **Error:** `{:error, "File already exists: /path/to/file.exs"}` (when `update: false`)

### Generated migration features

The generator creates Ecto migrations with:

- **Table creation:** `create table(...)` with correct options
- **Columns:** `add :col, :type, opts` with proper type mapping
- **Primary keys:** standard id (skipped), custom PKs, composite PKs
- **Foreign keys:** `references(:table, column: :col)` with automatic indexes
- **Timestamps:** `timestamps()` for `created_at`/`updated_at`
- **Constraints:** `null: false`, `unique: true`, `default` values
- **Indexes:** explicit indexes from DBML, automatic FK indexes
- **Ordering:** topological sort ensures referenced tables are created first

### Migration versioning workflow

Migrations are **append-only and audit-preserving:**

```elixir
# Day 1: Create initial schema
schema_v1 = """
table users {
  id int [pk]
  name varchar
}
"""

{:ok, tokens_v1} = DBML.parse(schema_v1)
{:ok, [users_mig]} =
  DBML.generate_ecto_migrations(tokens_v1, "priv/repo/migrations", "MyApp.Repo")
# Creates: 20000101000001_create_users.exs

# Day 2: Add column to users, add posts table
schema_v2 = """
table users {
  id int [pk]
  name varchar
  email varchar
}

table posts {
  id int [pk]
  user_id int [ref: > users.id]
  title varchar
}
"""

{:ok, tokens_v2} = DBML.parse(schema_v2)
{:ok, new_migs} =
  DBML.generate_ecto_migrations(tokens_v2, "priv/repo/migrations", "MyApp.Repo", update: true)
# Creates: 20000101000002_create_users.exs (users changed, new migration)
#          20000101000002_create_posts.exs (posts is new)
# Keeps:   20000101000001_create_users.exs (original, unchanged)

# Database migration history preserved:
# → 20000101000001_create_users.exs
# → 20000101000002_create_users.exs  (alter users table)
# → 20000101000002_create_posts.exs  (create posts table)
```

---

## Generating DBML from Ecto Schemas

Generate a DBML schema file from existing Ecto schema files. This is the reverse operation: instead of parsing DBML and generating schemas, read Ecto schemas and produce DBML.

### Basic usage

```elixir
# Generate DBML from all .ex files in a directory
{:ok, output_path} = DBML.schemas_to_dbml(
  "lib/my_app/schema",
  "schema.dbml"
)
```

### With options

```elixir
{:ok, output_path} = DBML.schemas_to_dbml(
  "lib/my_app/schema",
  "schema.dbml",
  project_name: "MyApp",
  database_type: "PostgreSQL"
)
```

### Options

#### `:project_name` (string, optional)

Adds a project block to the generated DBML with metadata.

```elixir
{:ok, output_path} = DBML.schemas_to_dbml(
  "lib/my_app/schema",
  "schema.dbml",
  project_name: "MyApp"
)

# Generates:
# project MyApp {
#   database_type: "PostgreSQL"
# }
```

#### `:database_type` (string, default: `"PostgreSQL"`)

Sets the database type in the project block.

```elixir
{:ok, output_path} = DBML.schemas_to_dbml(
  "lib/my_app/schema",
  "schema.dbml",
  project_name: "MyApp",
  database_type: "MySQL"
)
```

### Supported Ecto features

The generator reads Ecto schemas and extracts:

- **Primary keys:** standard `id int [pk]`, custom PKs with `@primary_key`, autoincrement
- **No primary key:** `@primary_key false`
- **Field types:** full mapping of Ecto types to DBML (integer, string, boolean, float, decimal, date, datetime, uuid, jsonb, etc.)
- **Field constraints:** `null: false`, `unique: true`, default values
- **Ecto.Enum fields:** extracted with all enum values
- **Timestamps:** `created_at` and `updated_at` columns
- **Associations:** `belongs_to` generates foreign key columns and `ref:` statements
- **Custom foreign keys:** respects `foreign_key:` options in associations
- **Type back-mapping:** Ecto atom types (`:integer`, `:string`, etc.) → DBML strings (`"int"`, `"varchar"`, etc.)

### Example

**Input schema files:**

```elixir
# lib/my_app/schema/user.ex
defmodule MyApp.Schema.User do
  use Ecto.Schema

  schema "users" do
    field :email, :string, null: false, unique: true
    field :status, Ecto.Enum, values: [:active, :inactive, :pending]
    timestamps()
  end
end

# lib/my_app/schema/post.ex
defmodule MyApp.Schema.Post do
  use Ecto.Schema

  schema "posts" do
    field :title, :string, null: false
    field :content, :string
    belongs_to :user, MyApp.Schema.User
    timestamps()
  end
end
```

**Generation:**

```elixir
{:ok, path} = DBML.schemas_to_dbml(
  "lib/my_app/schema",
  "schema.dbml",
  project_name: "MyApp"
)
```

**Output DBML:**

```dbml
project MyApp {
  database_type: "PostgreSQL"
}

enum status {
  active
  inactive
  pending
}

table users {
  id int [pk]
  email varchar [not null, unique]
  status status
  created_at timestamp
  updated_at timestamp
}

table posts {
  id int [pk]
  title varchar [not null]
  content varchar
  user_id int [ref: > users.id]
  created_at timestamp
  updated_at timestamp
}

ref: posts.user_id > users.id
```

### Return value

- **Success:** `{:ok, output_path}` — Path to the written `.dbml` file
- **Error:** `{:error, reason}` — File I/O or parsing error

### Use cases

**Visualize existing schemas:**
Generate DBML from production Ecto schemas and visualize them in [dbdiagram.io](https://dbml.dbdiagram.io/home).

**Document schemas:**
Keep a DBML representation of your database schema in version control.

**Migrate between tools:**
Convert Ecto schemas to DBML, then use DBML tools for schema design and visualization.

**Round-trip testing:**
Parse DBML → generate schemas → read schemas → generate DBML to verify round-trip fidelity.

---

## Type Mapping

### DBML to Ecto Type Mapping

| DBML Type | Ecto Type | Notes |
|-----------|-----------|-------|
| `int`, `integer`, `smallint`, `bigint` | `:integer` | |
| `varchar`, `char`, `text`, `character varying` | `:string` | |
| `boolean`, `bool` | `:boolean` | |
| `float`, `double`, `real` | `:float` | |
| `decimal`, `numeric` | `:decimal` | |
| `date` | `:date` | |
| `datetime`, `timestamp`, `timestamptz` | `:datetime` | |
| `time` | `:time` | |
| `uuid` | `:uuid` | Binary UUID type |
| `json`, `jsonb` | `:map` | |
| `serial`, `bigserial` | `:integer` | Auto-increment in migrations |

### Enum mapping

DBML enums are converted to Ecto.Enum fields:

```dbml
enum product_status {
  out_of_stock
  in_stock
  running_low
}

table products {
  id int [pk]
  status product_status
}
```

Generates:

```elixir
defmodule MyApp.Product do
  use Ecto.Schema

  schema "products" do
    field :status, Ecto.Enum, values: [:out_of_stock, :in_stock, :running_low]
  end
end
```

---

## Examples

### Complete schema example

**schema.dbml:**

```dbml
project CMS {
  database_type: "PostgreSQL"
  note: "Content management system"
}

enum post_status {
  draft
  published
  archived
}

table users {
  id int [pk, increment]
  email varchar [unique, not null]
  full_name varchar
  created_at timestamp
  updated_at timestamp
}

table posts {
  id int [pk, increment]
  user_id int [ref: > users.id, not null]
  title varchar [not null]
  content text
  status post_status [default: 'draft']
  published_at datetime
  created_at timestamp
  updated_at timestamp

  indexes {
    (user_id, status)
    published_at [type: btree]
  }
}

table comments {
  id int [pk, increment]
  post_id int [ref: > posts.id, not null]
  user_id int [ref: > users.id, not null]
  content text [not null]
  created_at timestamp
  updated_at timestamp
}
```

**Generate schemas:**

```elixir
{:ok, tokens} = DBML.parse_file("schema.dbml")

{:ok, paths} = DBML.generate_ecto_schemas(
  tokens,
  "lib/cms/schema",
  namespace: "CMS.Schema"
)

# Creates:
# - lib/cms/schema/users.ex
# - lib/cms/schema/posts.ex
# - lib/cms/schema/comments.ex
```

**Generate migrations:**

```elixir
{:ok, paths} = DBML.generate_ecto_migrations(
  tokens,
  "priv/repo/migrations",
  "CMS.Repo"
)

# Creates:
# - priv/repo/migrations/20000101000001_create_users.exs
# - priv/repo/migrations/20000101000002_create_posts.exs
# - priv/repo/migrations/20000101000003_create_comments.exs
# (topological order: users first, then posts, then comments)
```

### Handling schema evolution

```elixir
# Initial schema
initial_schema = DBML.parse_file("schema.dbml")

# Generate all artifacts
DBML.generate_ecto_schemas(
  initial_schema,
  "lib/my_app/schema",
  namespace: "MyApp",
  update: false  # fail if files exist
)

DBML.generate_ecto_migrations(
  initial_schema,
  "priv/repo/migrations",
  "MyApp.Repo",
  update: false  # fail if files exist
)

# ... run migrations, commit ...

# Later: schema evolves
evolved_schema = DBML.parse_file("schema.dbml")

# Update schemas safely (only changed files rewritten)
DBML.generate_ecto_schemas(
  evolved_schema,
  "lib/my_app/schema",
  namespace: "MyApp",
  update: true  # overwrite changed, skip unchanged
)

# Update migrations intelligently (append-only)
DBML.generate_ecto_migrations(
  evolved_schema,
  "priv/repo/migrations",
  "MyApp.Repo",
  update: true  # new files for changed tables, skip unchanged
)
```

---

## API Reference

### DBML module

#### `parse(dbml_string) :: {:ok, tokens} | {:error, reason}`

Parse a DBML schema from a string.

**Parameters:**
- `dbml_string` (string) — DBML schema definition

**Returns:**
- `{:ok, tokens}` — Parsed tokens (keyword list)
- `{:error, reason}` — Parse error details

```elixir
{:ok, tokens} = DBML.parse("""
  table users {
    id int [pk]
  }
""")
```

#### `parse_file(filepath) :: {:ok, tokens} | {:error, reason}`

Parse a DBML schema from a file.

**Parameters:**
- `filepath` (string) — Path to `.dbml` file

**Returns:**
- `{:ok, tokens}` — Parsed tokens
- `{:error, reason}` — File read or parse error

```elixir
{:ok, tokens} = DBML.parse_file("priv/schema.dbml")
```

#### `generate_ecto_schemas(tokens, output_dir, opts) :: {:ok, paths} | {:error, reason}`

Generate Ecto schema files from parsed DBML tokens.

**Parameters:**
- `tokens` (keyword list) — From `parse/1` or `parse_file/1`
- `output_dir` (string) — Directory to write `.ex` files
- `opts` (keyword list, optional) — Generation options

**Options:**
- `:namespace` (string) — Module namespace prefix
- `:singularize` (boolean, default: `true`) — Singularize table names
- `:update` (boolean, default: `false`) — Allow overwriting existing files

**Returns:**
- `{:ok, [paths]}` — List of written file paths
- `{:error, "File already exists: ..."}` — When `update: false` and file exists

```elixir
{:ok, paths} = DBML.generate_ecto_schemas(
  tokens,
  "lib/my_app/schema",
  namespace: "MyApp.Schema",
  singularize: true,
  update: false
)
```

#### `generate_ecto_migrations(tokens, output_dir, repo_module, opts) :: {:ok, paths} | {:error, reason}`

Generate Ecto migration files from parsed DBML tokens.

**Parameters:**
- `tokens` (keyword list) — From `parse/1` or `parse_file/1`
- `output_dir` (string) — Directory to write `.exs` migration files
- `repo_module` (string) — Repo module name (e.g., `"MyApp.Repo"`)
- `opts` (keyword list, optional) — Generation options

**Options:**
- `:base_timestamp` (integer, default: `20000101000000`) — Migration timestamp base
- `:update` (boolean, default: `false`) — Incremental generation

**Returns:**
- `{:ok, [paths]}` — List of written migration file paths
- `{:error, "File already exists: ..."}` — When `update: false` and file exists

```elixir
{:ok, paths} = DBML.generate_ecto_migrations(
  tokens,
  "priv/repo/migrations",
  "MyApp.Repo",
  base_timestamp: 20_250_101_000_000,
  update: true
)
```

#### `schemas_to_dbml(input_dir, output_path, opts) :: {:ok, output_path} | {:error, reason}`

Generate a DBML schema file from existing Ecto schema files.

Reads all `*.ex` files in `input_dir` that contain `use Ecto.Schema`, parses their structure, and writes a single `.dbml` file to `output_path`.

**Parameters:**
- `input_dir` (string) — Directory containing Ecto schema `.ex` files
- `output_path` (string) — Path to write the generated `.dbml` file
- `opts` (keyword list, optional) — Generation options

**Options:**
- `:project_name` (string, optional) — Name for the DBML project block
- `:database_type` (string, default: `"PostgreSQL"`) — Database type for project block

**Returns:**
- `{:ok, output_path}` — Path to the written `.dbml` file
- `{:error, reason}` — File I/O or parsing error

```elixir
{:ok, path} = DBML.schemas_to_dbml(
  "lib/my_app/schema",
  "schema.dbml",
  project_name: "MyApp",
  database_type: "PostgreSQL"
)
```

---

## DBML Syntax Reference

For complete DBML syntax documentation, see the official [DBML Documentation](https://dbml.dbdiagram.io/docs).

### Quick reference

```dbml
project ProjectName {
  database_type: "PostgreSQL"
  note: "Project description"
}

enum status_enum {
  active
  inactive
  pending
}

table users as U {
  id int [pk, increment]
  email varchar [unique, not null]
  name varchar
  status status_enum [default: 'active']
  created_at timestamp
  updated_at timestamp

  note: "User accounts table"

  indexes {
    email [unique]
    (status, created_at)
  }
}

table posts {
  id int [pk, increment]
  user_id int [ref: > U.id, not null]
  title varchar [not null]
  content text

  indexes {
    user_id
  }
}

ref: users.id < posts.user_id [comment: "One user has many posts"]
```

---

## Common Use Cases

### For a new Phoenix project (using CLI)

```bash
# 1. Create your DBML schema
cat > priv/schema.dbml << 'EOF'
table users {
  id int [pk]
  email varchar [unique, not null]
  created_at timestamp
  updated_at timestamp
}
EOF

# 2. Build the escript (or use mix tasks)
mix escript.build

# 3. Generate migrations
./dbml migrations priv/schema.dbml -o priv/repo/migrations -r MyApp.Repo

# 4. Generate schemas
./dbml schemas priv/schema.dbml -o lib/my_app/schema --namespace MyApp

# 5. Run migrations
mix ecto.migrate
```

Alternatively, use Mix tasks:
```bash
mix dbml.migrations priv/schema.dbml -o priv/repo/migrations -r MyApp.Repo
mix dbml.schemas priv/schema.dbml -o lib/my_app/schema --namespace MyApp
mix ecto.migrate
```

### For a new Phoenix project (using Elixir)

```bash
# 1. Create your DBML schema (same as above)

# 2. In iex:
iex> {:ok, tokens} = DBML.parse_file("priv/schema.dbml")
iex> DBML.generate_ecto_migrations(tokens, "priv/repo/migrations", "MyApp.Repo")
iex> DBML.generate_ecto_schemas(tokens, "lib/my_app/schema", namespace: "MyApp")

# 3. Run migrations
mix ecto.migrate
```

### For an existing project (using CLI)

```bash
# 1. Edit your DBML schema
# vim priv/schema.dbml

# 2. Regenerate using the escript (or mix tasks)
./dbml schemas priv/schema.dbml -o lib/my_app/schema --namespace MyApp --update true
./dbml migrations priv/schema.dbml -o priv/repo/migrations -r MyApp.Repo --update true

# 3. Review and run new migrations
mix ecto.migrate
```

Using Mix tasks:
```bash
mix dbml.schemas priv/schema.dbml -o lib/my_app/schema --namespace MyApp --update true
mix dbml.migrations priv/schema.dbml -o priv/repo/migrations -r MyApp.Repo --update true
mix ecto.migrate
```

### For an existing project (using Elixir)

```elixir
# Update DBML, then regenerate:
{:ok, tokens} = DBML.parse_file("priv/schema.dbml")

DBML.generate_ecto_schemas(
  tokens,
  "lib/my_app/schema",
  namespace: "MyApp",
  update: true  # overwrite changed, skip unchanged
)

DBML.generate_ecto_migrations(
  tokens,
  "priv/repo/migrations",
  "MyApp.Repo",
  update: true  # create new migrations for changed tables
)

# Review and run new migrations
mix ecto.migrate
```

### For visualizing existing schemas (using CLI)

```bash
# 1. Generate DBML from your existing Ecto schemas
./dbml file lib/my_app/schema -o priv/schema.dbml --project-name MyApp

# 2. View it online at https://dbml.dbdiagram.io/home
# Copy the contents of priv/schema.dbml and paste it into the editor
```

Or using Mix task:
```bash
mix dbml.file lib/my_app/schema -o priv/schema.dbml --project-name MyApp
```

### For visualizing existing schemas (using Elixir)

```elixir
# Generate DBML from your existing Ecto schemas
{:ok, path} = DBML.schemas_to_dbml("lib/my_app/schema", "priv/schema.dbml", project_name: "MyApp")

# View it online at https://dbml.dbdiagram.io/home
# Copy the contents of priv/schema.dbml and paste it into the editor
```

### Migrating from Ecto schemas to DBML-first workflow (using CLI)

```bash
# 1. Visualize current schemas
./dbml file lib/my_app/schema -o schema.dbml --project-name MyApp

# 2. Use the DBML as the source of truth going forward
# Edit schema.dbml with new changes

# 3. Generate schemas and migrations from DBML
./dbml schemas schema.dbml -o lib/my_app/schema --namespace MyApp --update true
./dbml migrations schema.dbml -o priv/repo/migrations -r MyApp.Repo --update true

# 4. Run migrations
mix ecto.migrate
```

Or using Mix tasks:
```bash
mix dbml.file lib/my_app/schema -o schema.dbml --project-name MyApp
# Edit schema.dbml...
mix dbml.schemas schema.dbml -o lib/my_app/schema --namespace MyApp --update true
mix dbml.migrations schema.dbml -o priv/repo/migrations -r MyApp.Repo --update true
mix ecto.migrate
```

### Migrating from Ecto schemas to DBML-first workflow (using Elixir)

```elixir
# 1. Visualize current schemas
{:ok, _path} = DBML.schemas_to_dbml("lib/my_app/schema", "schema.dbml", project_name: "MyApp")

# 2. Use the DBML as the source of truth going forward
# Edit schema.dbml with new changes

# 3. Generate schemas and migrations from DBML
{:ok, tokens} = DBML.parse_file("schema.dbml")
DBML.generate_ecto_schemas(tokens, "lib/my_app/schema", namespace: "MyApp", update: true)
DBML.generate_ecto_migrations(tokens, "priv/repo/migrations", "MyApp.Repo", update: true)

# 4. Run migrations
mix ecto.migrate
```

---

## Troubleshooting

### "File already exists" error

When regenerating schemas or migrations, use `update: true` to allow overwrites:

```elixir
# ❌ This fails if files exist
DBML.generate_ecto_schemas(tokens, "lib/my_app/schema")

# ✅ This overwrites changed files
DBML.generate_ecto_schemas(tokens, "lib/my_app/schema", update: true)
```

### Migration ordering with foreign keys

The generator automatically orders migrations using topological sort to ensure referenced tables are created before tables that reference them. This respects table aliases in DBML.

### Column/table names with spaces

Names with spaces are converted to snake_case in generated code:

```dbml
table "user accounts" {
  "full name" varchar
}
```

Generates:

```elixir
schema "user accounts" do
  field :full_name, :string
end
```

---

## Contributing

Contributions are welcome! Please open an issue or pull request on [GitHub](https://github.com/saleyn/dbml-ex).

---

## License

Apache-2.0

---

## References

- [DBML Official Documentation](https://dbml.dbdiagram.io/docs)
- [DBML Visualization Tool](https://dbml.dbdiagram.io/home)
- [Ecto Documentation](https://hexdocs.pm/ecto/)
- [Phoenix Framework](https://www.phoenixframework.org/)
