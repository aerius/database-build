# database-build

Build tooling for PostgreSQL database projects.

## Convention over configuration

`Build.rb` and `SyncDBData.rb` must be run from the **product source folder**: the folder containing `src/build/`. The layout below is fixed and cannot be configured:

```text
<source folder>/              # current directory
  src/build/                  # build config
    profiles/                 # product settings, one file per profile
      latest.rb
    externals/
      modules.rb              # used automatically when present
    config/
      AppSettings.rb
      UserSettings.rb         # optional
    scripts/                  # runscripts
  src/main/sql/<product>/     # database structure, shared by all profiles
  src/data/sql/<profile>/     # data set of one profile, entry point load.rb
```

A profile is a Ruby file `src/build/profiles/<profile>.rb`; the **profile name is that file name without `.rb`** (`latest.rb` → profile `latest`).

The profile argument is only that name (`latest`); a file name (`latest.rb`) or path is refused. It is optional when `profiles/` holds exactly one profile.

The profile name also selects the data set: profile `latest` loads `src/data/sql/latest/load.rb`, profile `integration-test` loads `src/data/sql/integration-test/load.rb`. `Build.rb` (`load_data`) and `SyncDBData.rb` (which dbdata files to fetch) both follow it. Data shared between profiles belongs in the internal modules data folder (`../modules/src/data/sql`), which `run_sql` searches after the profile's data folder.

```text
src/build/profiles/
  latest.rb             → src/data/sql/latest/
  integration-test.rb   → src/data/sql/integration-test/
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
| `db` | Database connection and naming (PostgreSQL) |
| `sync` | Sync modes and implementations (e.g. `sync.https`) |
| `tools` | Ancillary tooling and build behaviour |
| `session` | Per-run invocation state |

Field names and defaults: see [`bin/BuildConfig.rb`](bin/BuildConfig.rb).

The common SQL and data paths used by the build are derived: internal, then external (in modules file order), then builtin.

Common module locations (each type its own entry):

- **Internal** (beside product source) — optional. Next to the source folder: `../modules/src/main/sql` and `../modules/src/data/sql`.
- **External** — optional. Declared in `src/build/externals/modules.rb` beside `profiles/` (any HTTPS repo; sql/data paths inside each repo are fixed: `source/modules/src/{main,data}/sql`). Materialized under `<output.target_path>/externals/`.
- **Builtin** (SQL only) — required. `database-build/common/src/main/sql`.

The workspace is the parent of the `database-build` checkout. Product repos, external module repos, and the `dbdata/` folder usually live there as siblings. Dev builds copy external modules from siblings of the **product** git root (normally the same workspace).

### External modules file

Fixed path: `src/build/externals/modules.rb`. No settings assignment.

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

Build and SyncDBData materialize external common modules under `<output.target_path>/externals/`.

| Mode | Externals come from |
|------|---------------------|
| Dev (default) | Copy from sibling checkouts of the product git root (local edits included; not forced to `git_reference`) |
| Clean (`--flags clean` / Docker) | `git clone` + checkout each `git_reference` |

```bash
# From the product source folder; profile name under src/build/profiles/ (optional with one profile)
cd <product source folder>

# Dev
ruby ../database-build/bin/SyncDBData.rb latest --to-local
ruby ../database-build/bin/Build.rb default latest --version '#'

# Clean
ruby ../database-build/bin/Build.rb default latest --flags clean --version '#'
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

`docker/build-database.sh` always passes `--flags clean` (clone external modules at pinned `git_reference`). The image includes `git` and `openssh` for product/externals clones. Whether the product/`DBSOURCE` tree is cloned is separate:

| `CLONE_DBSOURCE` | When | Product / `DBSOURCE` |
|------------------|------|----------------------|
| `false` | `DBSOURCE_PATH` directory present | Local COPY/mount |
| `true` | directory missing | `git clone` product repo (`GIT_*`), then paths are prefixed with `GIT_REPOSITORY` |

`DBSOURCE_PATH` is the product source folder; the scripts run from there. `DBPROFILE` selects the profile under `src/build/profiles/` (optional when there is only one). Both modes write `$build_config.layout.dbdata_path` from `DBDATA_PATH` into `<DBSOURCE_PATH>/src/build/config/UserSettings.rb`.

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
  -w /work/<product>/<source folder> \
  aerius-database-build:<tag> \
  ruby /aerius-database-build/bin/Build.rb default latest \
    --database-name=local \
    --version=local
```

Do not pass `--flags clean` unless you want pinned clones. Non-clean materialization only needs the sibling directories on the volume (`git` is in the image but unused for that path).

## Build script

### Reproducible builds — git hashes and uncommitted state

When using Build.rb directly, a database is not 100% reproducible (uncommitted changes). As a first step, the build can store the git hashes of all common module repositories and whether there were uncommitted changes.

When your runscript calls `add_build_constants`, the build stores:

- **CURRENT_BUILD_COMMON_MODULE_REPO_HASHES** — A JSON string with one entry per common module repository (from the derived common SQL and data paths). Each entry has `repo_url`, `commit_hash`, `sql_paths` (array), `data_paths` (array), and `had_uncommitted_changes`. A repository can have multiple paths, so the path arrays can have more than one element. Paths are relative to the git repository root, not to the project settings file.

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
