# database-build

Build tooling for PostgreSQL database projects.

## Convention over configuration

`Build.rb` and `SyncDBData.rb` must be run from the product source folder: the folder containing `src/build/`.

The layout below is fixed and cannot be configured:
```text
<source folder>/              # current directory
  src/build/                  # build config
    profiles/                 # product settings, one file per profile
      latest.rb
    config/
      AppSettings.rb
      UserSettings.rb         # optional
    scripts/                  # runscripts
  src/main/sql/<product>/     # database structure, shared by all profiles
  src/data/sql/<profile>/     # data set of one profile, entry point load.rb
```

A profile is a Ruby file `src/build/profiles/<profile>.rb`; the profile name is that file name without `.rb` (`latest.rb` -> profile `latest`).

The profile argument is only that name (`latest`); a file name (`latest.rb`) or path is refused.

It is optional when `profiles/` holds exactly one profile.

The profile name also selects the data set: profile `latest` loads `src/data/sql/latest/load.rb`, profile `integration-test` loads `src/data/sql/integration-test/load.rb`.

`Build.rb` (`load_data`) and `SyncDBData.rb` (which dbdata files to fetch) both follow it.

Data shared between profiles belongs in the internal modules data folder (`../modules/src/data/sql`), which `run_sql` searches after the profile's data folder.

```text
src/build/profiles/
  latest.rb             - src/data/sql/latest/
  integration-test.rb   - src/data/sql/integration-test/
src/main/sql/<product>/ # same for both
```

A profile only needs:

```ruby
$build_config.product = :example_product
```

All settings are stored on `$build_config` (`BuildConfig.rb`) in groups. Settings files should assign into `$build_config`.

| Group | Description |
|---|---|
| `product` | Product identity |
| `layout` | Where source, modules, data, and scripts live |
| `output` | Where build artifacts and logs are written |
| `postgres` | Database connection and naming (PostgreSQL) |
| `sync` | Sync modes and implementations (e.g. `sync.https`) |
| `tools` | Ancillary tooling and build behaviour |
| `session` | Per-run invocation state |

Field names and defaults: see [`bin/BuildConfig.rb`](bin/BuildConfig.rb).

The common SQL and data paths used by the build are derived: internal, then external, then builtin.

Common module locations (each type its own entry):

- **Internal** (beside product source) — optional. Next to the source folder: `../modules/src/main/sql` and `../modules/src/data/sql`.
- **External** — optional. For now: fixed checkout name `database-modules` next to `database-build`, with fixed paths inside that repo: `source/modules/src/main/sql` and `source/modules/src/data/sql` (i.e. ` /database-modules/source/modules/src/{main,data}/sql`).
- **Builtin** (SQL only) — required. `database-build/common/src/main/sql`.

The workspace is the parent of the `database-build` checkout (sibling repos such as `database-modules` and `dbdata` live there).

```bash
# From the product source folder; profile name under src/build/profiles/ (optional with one profile)
# Usual layout: <workspace>/<product repo>/source/database/<database product folder>
cd <workspace>/<product repo>/source/database/<database product folder>

ruby ../../../../database-build/bin/SyncDBData.rb latest --to-local
ruby ../../../../database-build/bin/Build.rb default latest --version '#'
```

### Overridable settings

Typical `AppSettings.rb` / `UserSettings.rb` assignments:
- `$build_config.layout.dbdata_path` (default `<workspace>/dbdata/`)
- `$build_config.postgres.name_prefix` (default `AERIUS`)
- `$build_config.postgres.username` / `.password` (default `aerius`)
- `$build_config.sync.source` / `.target` (default `:https` / `:local`)
- `$build_config.sync.https.data_path` / `.username` / `.password`

`SyncDBData.rb --from-https` downloads into `$build_config.layout.dbdata_path` from `$build_config.sync.https.data_path` (or from `--from-https` / `--to-local` when given).

### Docker

`DBSOURCE_PATH` is the product source folder; `docker/build-database.sh` runs the scripts from there.

`DBPROFILE` selects the profile under `src/build/profiles/` (optional when there is only one).

The script writes `$build_config.layout.dbdata_path` from `DBDATA_PATH` into `<DBSOURCE_PATH>/src/build/config/UserSettings.rb`, so the image does not depend on the workspace `dbdata/` convention.

## Build script

### Reproducible builds — git hashes and uncommitted state

When using Build.rb directly, a database is not 100% reproducible (uncommitted changes). As a first step, the build can store the git hashes of all common module repositories and whether there were uncommitted changes.

When your runscript calls `add_build_constants`, the build stores:
- **CURRENT_BUILD_COMMON_MODULE_REPO_HASHES** — A JSON string with one entry per common module repository (from the derived common SQL and data paths). Each entry has `repo_url`, `commit_hash`, `sql_paths` (array), `data_paths` (array), and `had_uncommitted_changes`. A repository can have multiple paths, so the path arrays can have more than one element. Paths are relative to the git repository root, not to the project settings file.
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
