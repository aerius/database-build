# database-build

Build tooling for PostgreSQL database projects.

## Convention over configuration

Product settings only need:

```ruby
$product = :calculator_nl
$source_path = '.'
$build_config_path = 'src/build'
```

Paths may be relative to the product `settings.rb` directory.

`$build_config_path` has a fixed layout:

```text
$build_config_path/
  config/
    AppSettings.rb
    UserSettings.rb   # optional
  scripts/            # runscripts
```

Other layout paths are **fixed** from constants in `bin/PathConventions.rb`:

| Variable | Convention |
|---|---|
| `$product_sql_path` | `$source_path/src/main/sql/<product>/` |
| `$product_data_path` | `$source_path/src/data/sql/<product>/` |
| `$common_sql_paths` | existing among in-repo `…/sql/common/`, sibling `database-modules/source/modules/src/main/sql`, and `database-build/common/src/main/sql` |
| `$common_data_paths` | existing among in-repo `…/data/sql/common/` and sibling `database-modules/…/src/data/sql` |
| `$runscripts_path` | `$build_config_path/scripts/` |

The workspace root is the parent directory of the `database-build` checkout (sibling repos such as `database-modules` and `dbdata` live there).

### Overridable settings

Only these layout-related settings may be overridden (defaults still apply when unset):

- `$dbdata_path` — local datasource folder; default `<workspace>/dbdata/`. Use an absolute path when the data lives elsewhere, e.g. `/data/aerius/dbdata/`.
- `$database_name_prefix` — default `AERIUS`

Typical `AppSettings.rb` / `UserSettings.rb` overrides otherwise:

- `$pg_username` / `$pg_password` (default `aerius`)
- `$https_data_path` — **full** HTTPS base URL of the remote dbdata folder (no separate dir segment is appended); set in `AppSettings.rb`
- `$https_data_username` / `$https_data_password` — set in `UserSettings.rb` when required

`SyncDBData.rb --from-https` downloads into `$dbdata_path` from `$https_data_path` (or from `--from-https` / `--to-local` when given).

### Docker

`docker/build-database.sh` always writes `$dbdata_path` from `DBDATA_PATH` into `UserSettings.rb` under `DBCONFIG_PATH` (the `config/` directory), so the image does not depend on the workspace `dbdata/` convention.

## Build script

### Reproducible builds — git hashes and uncommitted state

When using Build.rb directly, a database is not 100% reproducible (uncommitted changes). As a first step, the build can store the git hashes of all common module repositories and whether there were uncommitted changes.

When your runscript calls `add_build_constants`, the build stores:

- **CURRENT_BUILD_COMMON_MODULE_REPO_HASHES** — A JSON string with one entry per common module repository (from `$common_sql_paths` / `$common_data_paths`). Each entry has `repo_url`, `commit_hash`, `sql_paths` (array), `data_paths` (array), and `had_uncommitted_changes`. A repository can have multiple paths, so the path arrays can have more than one element. Paths are relative to the git repository root, not to the project settings file.

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
