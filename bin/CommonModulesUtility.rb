require 'pathname'
require 'json'
require 'GitUtility.rb'

##
# Utility for common-module repo hashes.
# Pairs sql and data paths by index.
#
class CommonModulesUtility

  # Build JSON { "common_modules": [ { repo_url, hash, sql_path, data_path, had_uncommitted_changes }, ... ] } from common_sql_paths and common_data_paths.
  # Pairs by index: entry i uses common_sql_paths[i] and common_data_paths[i].
  # Returns json_string.
  def self.build_repo_hashes(common_sql_paths, common_data_paths)
    return JSON.generate({ 'common_modules' => build_common_modules(common_sql_paths, common_data_paths) })
  end

  # Returns true if product_sql_path, product_data_path, or any common path repo has uncommitted changes.
  def self.any_had_uncommitted_changes?(product_sql_path, product_data_path, common_sql_paths, common_data_paths)
    paths = [product_sql_path, product_data_path] + common_sql_paths + common_data_paths
    paths.each { |path| return true if GitUtility.get_git_has_uncommitted_changes(path) }
    return false
  end

  # Returns array of common-module entry hashes (repo_url, hash, sql_path, data_path, had_uncommitted_changes), paired by index. If sql and data at an index have different git hashes, two separate entries are added.
  def self.build_common_modules(common_sql_paths, common_data_paths)
    common_modules = []
    n = [common_sql_paths.size, common_data_paths.size].max
    n.times do |i|
      common_modules.concat(entries_for_paths(common_sql_paths[i], common_data_paths[i]))
    end
    return common_modules
  end

  # Returns one or two entry hashes for the pair at (sql_path, data_path). Delegates to path_repo_info and entries_for_pair.
  def self.entries_for_paths(sql_path, data_path)
    return entries_for_pair(path_repo_info(sql_path), path_repo_info(data_path))
  end

  # Returns one or two entry hashes for a (sql_info, data_info) pair. Two entries when both present but different hash.
  def self.entries_for_pair(sql_info, data_info)
    # Common paths are validated earlier; at least one should be in a git repo.
    if sql_info.nil? && data_info.nil? then
      raise 'Common module path is missing or not in a git repo (path should already have been validated).'
    # Only data path in a repo: one entry (data only).
    elsif sql_info.nil? then
      return [entry(data_info[:repo_url], data_info[:hash], nil, data_info[:rel], data_info[:dirty])]
    # Only sql path in a repo: one entry (sql only).
    elsif data_info.nil? then
      return [entry(sql_info[:repo_url], sql_info[:hash], sql_info[:rel], nil, sql_info[:dirty])]
    # Different repos (different hash): two separate entries.
    elsif sql_info[:hash] != data_info[:hash] then
      return [
        entry(sql_info[:repo_url], sql_info[:hash], sql_info[:rel], nil, sql_info[:dirty]),
        entry(data_info[:repo_url], data_info[:hash], nil, data_info[:rel], data_info[:dirty])
      ]
    # Same repo: one entry with both sql and data paths.
    else
      dirty = (sql_info && sql_info[:dirty]) || (data_info && data_info[:dirty])
      return [entry(sql_info[:repo_url], sql_info[:hash], sql_info[:rel], data_info[:rel], dirty)]
    end
  end

  # Returns { repo_url, hash, rel, full, dirty } for path, or nil if not in a git repo.
  def self.path_repo_info(path)
    root = GitUtility.get_git_repo_root(path)
    # Not inside a git repo.
    return nil unless root
    hash = GitUtility.get_git_hash_for_path(path)
    repo_url = (GitUtility.get_git_remote_url(path) || '').to_s
    rel_path = Pathname.new(File.expand_path(path)).relative_path_from(Pathname.new(root)).to_s
    rel_path = nil if rel_path.to_s.empty?
    dirty = GitUtility.get_git_has_uncommitted_changes(path)
    return { repo_url: repo_url, hash: (hash || '').to_s, rel: rel_path, full: path, dirty: dirty }
  end

  # Builds one common_modules entry hash for the JSON. Normalizes nil repo_url/hash to ''.
  def self.entry(repo_url, hash, sql_path, data_path, had_uncommitted_changes)
    return {
      'repo_url' => (repo_url || '').to_s,
      'hash' => (hash || '').to_s,
      'sql_path' => sql_path,
      'data_path' => data_path,
      'had_uncommitted_changes' => had_uncommitted_changes
    }
  end

  private_class_method :build_common_modules, :entries_for_paths, :entries_for_pair, :path_repo_info, :entry
end
