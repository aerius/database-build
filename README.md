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
| `common_sql_paths` / `common_data_paths` | Arrays of dirs merged after `SettingsLoader.prepare` (internal + external + builtin) |
| `external_common_modules_file` | Optional path to a modules file (relative to product settings dir or absolute) |

Common module locations (each type its own entry):

- **Internal** (beside product source) — optional. Same parent as `<source_path>`: `modules/src/main/sql` and `modules/src/data/sql`.
- **External** — optional. Declared in a modules file via `layout.external_common_modules_file` (any HTTPS repo; sql/data paths inside each repo are fixed: `source/modules/src/{main,data}/sql`). Materialized under `<output.target_path>/externals/`.
- **Builtin** (SQL only) — required. `database-build/common/src/main/sql`.

The workspace is the parent of the `database-build` checkout. Product repos, external module repos, and the `dbdata/` folder usually live there as siblings. Dev builds copy external modules from siblings of the **product** git root (normally the same workspace).

### External modules file

Set in product or App settings:

```ruby
$build_config.layout.external_common_modules_file = 'externals/modules.rb'
```

Modules file content (assigns `$build_config.session.common_module_versions`):

```ruby
$build_config.session.common_module_versions = [
  {
    # plain HTTPS only — credentials via GIT_USERNAME / GIT_TOKEN, never in this file
    'git_repository' => 'https://github.com/aerius/database-modules.git',
    # commit hash, tag, or branch (clean builds: git clone + checkout)
    'git_reference' => 'v1.2.3',
  },
]
```

`SettingsLoader.prepare` (Build / SyncDBData) materializes external common modules under `output.target_path/externals/`.

| Mode | Externals come from |
|------|---------------------|
| Dev (default) | Copy from sibling checkouts of the product git root (local edits included; not forced to `git_reference`) |
| Clean (`--flags clean` / Docker) | `git clone` + checkout each `git_reference` |

```bash
# Dev
ruby bin/SyncDBData.rb path/to/settings.rb --to-local
ruby bin/Build.rb default path/to/settings.rb --version '#'

# Clean
ruby bin/Build.rb default path/to/settings.rb --flags clean --version '#'
```

### Overridable settings

Typical `AppSettings.rb` / `UserSettings.rb` assignments:

- `$build_config.layout.dbdata_path` (default `<workspace>/dbdata/`)
- `$build_config.layout.external_common_modules_file`
- `$build_config.postgres.name_prefix` (default `AERIUS`)
- `$build_config.postgres.username` / `.password` (default `aerius`)
- `$build_config.tools.https_data_path` / `.https_data_username` / `.https_data_password`

`SyncDBData.rb --from-https` downloads into `$build_config.layout.dbdata_path` from `$build_config.tools.https_data_path` (or from `--from-https` / `--to-local` when given).

### Docker

`docker/build-database.sh` always passes `--flags clean` (clone external modules at pinned `git_reference`). The image includes `git` and `openssh` for product/externals clones. Whether the product/`DBSOURCE` tree is cloned is separate:

| `CLONE_DBSOURCE` | When | Product / `DBSOURCE` |
|------------------|------|----------------------|
| `false` | `DBSOURCE_PATH` directory present | Local COPY/mount |
| `true` | directory missing | `git clone` product repo (`GIT_*`), then paths are prefixed with `GIT_REPOSITORY` |

Both modes write `$build_config.layout.dbdata_path` from `DBDATA_PATH` into `UserSettings.rb` under `DBCONFIG_PATH`.

### Docker image as a local build host

`/build-database.sh` is for reproducible product DB images and always uses `--flags clean`. Developers can also run the image only for Ruby + PostgreSQL and call `Build.rb` / `SyncDBData.rb` on mounted sources. Omit `--flags clean` to copy external modules from sibling checkouts (same as a host build).

Mount the workspace parent so the product repo and external module repos are siblings (and include `.git` on the product tree — needed to find the product git root):

```text
/work/<product-repo>/
/work/database-modules/    # sibling named after the repo basename
```

Example:

```bash
docker run --rm -it \
  -v /path/to/git:/work \
  aerius-database-build:<tag> \
  ruby /aerius-database-build/bin/Build.rb default \
    /work/<product>/path/to/settings.rb \
    --database-name=local \
    --version=local
```

Do not pass `--flags clean` unless you want pinned clones. Non-clean materialization only needs the sibling directories on the volume (`git` is in the image but unused for that path).

## Build script

### Reproducible builds — git hashes and uncommitted state

When using Build.rb directly, a database is not 100% reproducible (uncommitted changes). As a first step, the build can store the git hashes of all common module repositories and whether there were uncommitted changes.

When your runscript calls `add_build_constants`, the build stores:

- **CURRENT_BUILD_COMMON_MODULE_REPO_HASHES** — A JSON string with one entry per common module repository (from `$build_config.layout.common_sql_paths` / `$build_config.layout.common_data_paths`). Each entry has `repo_url`, `commit_hash`, `sql_paths` (array), `data_paths` (array), and `had_uncommitted_changes`. A repository can have multiple paths, so the path arrays can have more than one element. Paths are relative to the git repository root, not to the project settings file.

- **CURRENT_BUILD_SCRIPT_HAD_UNCOMMITTED_CHANGES** — `'true'` if the product sql path repository, product data path repository, or any common module repository had uncommitted or untracked changes; `'false'` otherwise.

- **CURRENT_BUILD_CLEAN_BUILD_USED** — `'true'` when the build was started with `--flags clean`; `'false'` otherwise.

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
