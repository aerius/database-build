require 'pathname'
require 'json'
require 'GitUtility.rb'

##
# Utility for common-module repo hashes.
# Groups paths by repo (repo_url + hash); one JSON entry per repository with sql_paths and data_paths arrays.
#
class CommonModulesUtility

  # Build JSON { "common_module_repos": [ { repo_url, hash, sql_paths, data_paths, had_uncommitted_changes }, ... ] } from common_sql_paths and common_data_paths. One entry per repo; paths are in sql_paths and data_paths arrays.
  # Returns json_string.
  def self.build_repo_hashes(common_sql_paths, common_data_paths)
    return JSON.generate({ 'common_module_repos' => build_common_module_repos(common_sql_paths, common_data_paths) })
  end

  # Returns true if product_sql_path, product_data_path, or any common path repo has uncommitted changes.
  def self.any_had_uncommitted_changes?(product_sql_path, product_data_path, common_sql_paths, common_data_paths)
    paths = [product_sql_path, product_data_path] + common_sql_paths + common_data_paths
    paths.each { |path| return true if GitUtility.get_git_has_uncommitted_changes(path) }
    return false
  end

  # Returns array of entry hashes (repo_url, hash, sql_paths, data_paths, had_uncommitted_changes), one per unique repo. Paths not in a git repo are skipped. Order: by repo_url, then hash.
  def self.build_common_module_repos(common_sql_paths, common_data_paths)
    groups = {}
    add_paths_to_groups(groups, common_sql_paths, :sql)
    add_paths_to_groups(groups, common_data_paths, :data)
    entries = groups.each_value.map { |g| entry(g[:repo_url], g[:hash], g[:sql_paths], g[:data_paths], g[:dirty]) }
    return entries.sort_by { |e| [e['repo_url'], e['hash']] }
  end

  # Adds path repo infos to groups keyed by [repo_url, hash]. Appends rel to sql_paths or data_paths and merges dirty.
  def self.add_paths_to_groups(groups, paths, type)
    Array(paths).each do |path|
      next if path.nil? || !File.exist?(path)
      info = path_repo_info(path)
      next if info.nil?
      key = [info[:repo_url], info[:hash]]
      groups[key] ||= { repo_url: info[:repo_url], hash: info[:hash], sql_paths: [], data_paths: [], dirty: false }
      groups[key][:sql_paths] << info[:rel] if type == :sql && info[:rel]
      groups[key][:data_paths] << info[:rel] if type == :data && info[:rel]
      groups[key][:dirty] = true if info[:dirty]
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

  # Builds one common_module_repos entry hash for the JSON. Normalizes nil repo_url/hash to ''.
  def self.entry(repo_url, hash, sql_paths, data_paths, had_uncommitted_changes)
    return {
      'repo_url' => (repo_url || '').to_s,
      'hash' => (hash || '').to_s,
      'sql_paths' => sql_paths,
      'data_paths' => data_paths,
      'had_uncommitted_changes' => had_uncommitted_changes
    }
  end

  private_class_method :build_common_module_repos, :add_paths_to_groups, :path_repo_info, :entry
end
