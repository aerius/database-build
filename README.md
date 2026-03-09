# database-build

Build tooling for PostgreSQL database projects.

## Build script

### Reproducible builds — git hashes and uncommitted state

When using Build.rb directly, a database is not 100% reproducible (uncommitted changes). As a first step, the build can store the git hashes of all common module repositories and whether there were uncommitted changes.

When your runscript calls `add_build_constants`, the build stores:

- **CURRENT_BUILD_COMMON_MODULE_REPO_HASHES** — A JSON string with one entry per common module repository (from `$common_sql_paths` / `$common_data_paths`). Each entry has `repo_url`, `hash`, `sql_path`, `data_path`, and `had_uncommitted_changes`. The `sql_path` and `data_path` values are relative to the git repository root of that module, not to the project settings file.

- **CURRENT_BUILD_SCRIPT_HAD_UNCOMMITTED_CHANGES** — `'true'` if the product sql path repository, product data path repository, or any common module repository had uncommitted or untracked changes; `'false'` otherwise.

Example JSON stored in CURRENT_BUILD_COMMON_MODULE_REPO_HASHES:

```json
{
  "common_module_repos": [
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

