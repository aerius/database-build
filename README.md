# database-build

Build tooling for PostgreSQL database projects.

## Convention over configuration

Product settings only need:

```ruby
$build_config.product = :calculator_nl
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

All settings are stored on `$build_config` (`BuildConfig`) in groups. Settings files assign into `$build_config` (no separate settings `$globals`).

| Group | Contents |
|---|---|
| `product` | product symbol |
| `layout` | `source_path`, `build_config_path`, `product_sql_path`, `product_data_path`, `common_sql_paths`, `common_data_paths`, `runscripts_path`, `dbdata_path`, settings file paths |
| `output` | `target_path`, `log_path`, `output_path`, `temp_path` |
| `postgres` | credentials, `bin_path`, template/tablespace/collation, `name_prefix`, function prefixes |
| `tools` | `git_bin_path`, HTTPS sync settings, `max_threads`, `on_uncommitted_changes`, `hint_level` |
| `session` | `product_settings_file`, `runscript_file`, `build_flags`, `dump_filetitle` |

Layout path conventions (under `layout`):

| Field | Convention |
|---|---|
| `product_sql_path` | `layout.source_path/src/main/sql/<product>/` |
| `product_data_path` | `layout.source_path/src/data/sql/<product>/` |
| `common_sql_paths` | existing among sibling `modules/src/main/sql` (next to `source_path`), sibling `database-modules/source/modules/src/main/sql`, and `database-build/common/src/main/sql` |
| `common_data_paths` | existing among sibling `modules/src/data/sql` (next to `source_path`) and sibling `database-modules/…/src/data/sql` |
| `runscripts_path` | `layout.build_config_path/scripts/` |

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
