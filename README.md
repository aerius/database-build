# database-build

Build tooling for PostgreSQL database projects.

## Build script

### Reproducible builds — git hashes and uncommitted state

When using Build.rb directly, a database is not 100% reproducible (uncommitted changes). As a first step, the build can store the git hashes of all common modules and whether there were uncommitted changes.

When your runscript calls `add_build_constants`, the build stores:

- **CURRENT_BUILD_COMMON_MODULES_REPO_HASHES** — A JSON string with one entry per common module (from `$common_sql_paths` / `$common_data_paths`). Each entry has `repo_url`, `hash`, `sql_path`, `data_path`, and `had_uncommitted_changes`.

  **Pairing:** SQL and data paths are paired by index: entry *i* uses `$common_sql_paths[i]` and `$common_data_paths[i]`. If that pair has different git hashes (different repos), two entries are stored (one sql-only, one data-only). We keep it this simple because common sql/data paths should be defined as pairs.

  **Paths in JSON:** The `sql_path` and `data_path` values are relative to the git repo root of that module, not to the project settings file.

- **CURRENT_BUILD_SCRIPT_HAD_UNCOMMITTED_CHANGES** — `'true'` if the product sql path repo, product data path repo, or any common module repo had uncommitted or untracked changes; `'false'` otherwise.

Example JSON stored in CURRENT_BUILD_COMMON_MODULES_REPO_HASHES:

```json
{
  "common_modules": [
    {
      "repo_url": "https://github.com/org/database-modules.git",
      "hash": "k1l2m3n4o5...",
      "sql_path": "source/modules/src/main/sql/",
      "data_path": "source/modules/src/data/sql/",
      "had_uncommitted_changes": false
    },
    {
      "repo_url": "https://github.com/org/project-x-database-modules.git",
      "hash": "p6q7r8s9t0...",
      "sql_path": "src/main/sql/",
      "data_path": "src/data/sql/",
      "had_uncommitted_changes": false
    }
  ]
}
```

## Common database modules

 [README.md](./common/README.md)

