# database-build

Build tooling for PostgreSQL database projects.

## Workflow

### Product settings

```ruby
# Optional in-repo commons
$internal_common_sql_paths = [...]
$internal_common_data_paths = [...]

# Optional external pins
$external_common_modules_file = File.join(File.dirname(__FILE__), '../externals/modules.rb')
```

**Breaking change from version 1.6 :** builds use pinned external module refs instead of relying on whatever external code happens to be checked out locally.

Modules file (`$common_module_versions`) — loaded from `$external_common_modules_file` when set:

```ruby
$common_module_versions = [
  {
    # plain HTTPS only
    # Never put credentials in the modules file and use `GIT_USERNAME` / `GIT_TOKEN` instead
    'git_repository' => 'https://github.com/aerius/database-modules.git',

    'git_reference' => 'abc123def456',
    'sql_path' => 'source/modules/src/main/sql/',
    'data_path' => 'source/modules/src/data/sql/',
  },
]
```

### Local builds

Dev layout — externals are **siblings** of the product git root:

```
git/
├── database-build
├── database-modules
└── MyProduct
```

```bash
# Dev (only copy siblings repos)
ruby bin/SyncDBData.rb path/to/settings.rb --to-local
ruby bin/Build.rb default path/to/settings.rb --version '#'

# Clean (only clone repos at pinned git_reference)
ruby bin/Build.rb default path/to/settings.rb --flags clean --version '#'
```

### Docker

`build-database.sh` always uses `--flags clean` (clone at pinned `git_reference`). Sibling checkouts are not required in the image.

## Background

### Prepare and materialize

`Globals.prepare!` (called by Build / SyncDBData / …) materializes externals under `target/externals/` and writes `.prepared.json` so a following script can reuse the same tree.

| Mode | Externals come from |
|------|---------------------|
| Dev (default) | Copy from sibling checkouts (local changes included; not pinned to `git_reference`) |
| Clean / Docker | `git clone` + checkout `git_reference` from the modules file |

### Uncommitted changes

Before building, uncommitted/untracked changes in the product and all common modules (including materialized externals) are detected. Behaviour is controlled by `$on_uncommitted_changes` (`:warn`, `:prompt`, or `:abort`; default `:warn`).

### Reproducible builds — git hashes and uncommitted state

When using Build.rb directly, a database is not 100% reproducible if there are uncommitted changes. As a first step, the build can store the git hashes of all common module repositories and whether there were uncommitted changes.

When your runscript calls `add_build_constants`, the build stores:

- **CURRENT_BUILD_COMMON_MODULE_REPO_HASHES** — A JSON string with one entry per common module repository. Each entry has `repo_url`, `commit_hash`, `sql_paths` (array), `data_paths` (array), and `had_uncommitted_changes`. A repository can have multiple paths, so the path arrays can have more than one element. Paths are relative to the git repository root, not to the product settings file.
- **CURRENT_BUILD_SCRIPT_HAD_UNCOMMITTED_CHANGES** — `'true'` if the product SQL path, product data path, or any common module repository had uncommitted or untracked changes; `'false'` otherwise.
- **CURRENT_BUILD_CLEAN_BUILD_USED** — `'true'` when the build was started with `--flags clean`; `'false'` otherwise.

Example JSON stored in `CURRENT_BUILD_COMMON_MODULE_REPO_HASHES`:

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

## Core database modules

Shared SQL modules that ship with the build tooling (`common/`): [common/README.md](./common/README.md)
