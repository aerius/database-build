# database-build

Build tooling for PostgreSQL database projects.

## Convention over configuration

Product settings only need:

```ruby
$build_config.product = :example_product
$build_config.layout.source_path = '.'
$build_config.layout.build_config_path = 'src/build'
```

Paths may be relative to the product `settings.rb` directory.

`$build_config.layout.build_config_path` has a fixed layout:

```text
build-config/
  config/
    AppSettings.rb
    UserSettings.rb   # optional
  scripts/            # runscripts
```

All settings are stored on `$build_config` (`BuildConfig.rb`) in groups. Settings files should assign into `$build_config` (no separate settings `$globals`).
Optional: set `layout.product_sql_path` / `layout.product_data_path` before finalize to override the `<product>` subfolder convention (paths relative to `source_path`).

| Group | Description |
|---|---|
| `product` | Product identity |
| `layout` | Where source, modules, data, and scripts live |
| `output` | Where build artifacts and logs are written |
| `postgres` | How to talk to PostgreSQL |
| `tools` | Ancillary tooling and build behaviour |
| `session` | Per-run invocation state |

Field names and defaults: see [`bin/BuildConfig.rb`](bin/BuildConfig.rb).

Layout path defaults (specified under `layout` in the `BuildConfig.rb`):

| Field | Convention |
|---|---|
| `product_sql_path` | `<source_path>/src/main/sql/<product>/` |
| `product_data_path` | `<source_path>/src/data/sql/<product>/` |
| `runscripts_path` | `<build_config_path>/scripts/` |
| `common_sql_paths` / `common_data_paths` | Arrays of dirs that exist from the locations below |

Common module locations (each type its own entry):

- **Internal** (beside product source) — optional. Same parent as `<source_path>`: `modules/src/main/sql` and `modules/src/data/sql`.
- **External** — optional. For now: fixed checkout name `database-modules` next to `database-build`, with fixed paths inside that repo: `source/modules/src/main/sql` and `source/modules/src/data/sql` (i.e. ` /database-modules/source/modules/src/{main,data}/sql`).
- **Builtin** (SQL only) — required. `database-build/common/src/main/sql`.

The workspace root is the parent directory of the `database-build` checkout (sibling repos such as `database-modules` and `dbdata` live there).

### Overridable settings

Typical `AppSettings.rb` / `UserSettings.rb` assignments:

- `$build_config.layout.dbdata_path` (default `<workspace>/dbdata/`)
- `$build_config.postgres.name_prefix` (default `AERIUS`)
- `$build_config.postgres.username` / `.password` (default `aerius`)
- `$build_config.tools.https_data_path` / `.https_data_username` / `.https_data_password`

`SyncDBData.rb --from-https` downloads into `$build_config.layout.dbdata_path` from `$build_config.tools.https_data_path` (or from `--from-https` / `--to-local` when given).

### Docker

`docker/build-database.sh` writes `$build_config.layout.dbdata_path` from `DBDATA_PATH` into `UserSettings.rb` under `DBCONFIG_PATH` (the `config/` directory), so the image does not depend on the workspace `dbdata/` convention.

## Build script

### Reproducible builds — git hashes and uncommitted state

When using Build.rb directly, a database is not 100% reproducible (uncommitted changes). As a first step, the build can store the git hashes of all common module repositories and whether there were uncommitted changes.

When your runscript calls `add_build_constants`, the build stores:

- **CURRENT_BUILD_COMMON_MODULE_REPO_HASHES** — A JSON string with one entry per common module repository (from `$build_config.layout.common_sql_paths` / `$build_config.layout.common_data_paths`). Each entry has `repo_url`, `commit_hash`, `sql_paths` (array), `data_paths` (array), and `had_uncommitted_changes`. A repository can have multiple paths, so the path arrays can have more than one element. Paths are relative to the git repository root, not to the project settings file.

- **CURRENT_BUILD_SCRIPT_HAD_UNCOMMITTED_CHANGES** — `'true'` if the product sql path repository, product data path repository, or any common module repository had uncommitted or untracked changes; `'false'` otherwise.

Example JSON stored in CURRENT_BUILD_COMMON_MODULE_REPO_HASHES:

```json
{
  "common_module_repos": [
    {
      "repo_url": "https://github.com/org/database-modules.git",
      "commit_hash": "k1l2m3n4o5...",
      "sql_paths": ["source/modules/src/main/sql/"],
      "data_paths": ["source/modules/src/data/sql/"],
      "had_uncommitted_changes": false
    }
  ]
}
```

## Common database modules

[README.md](./common/README.md)
