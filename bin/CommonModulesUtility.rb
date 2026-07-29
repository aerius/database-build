require 'pathname'
require 'json'
require 'fileutils'
require 'GitUtility.rb'

##
# Utility for common-module repo hashes and external common-module materialization.
# Groups paths by repo (repo_url + hash); one JSON entry per repository with sql_paths and data_paths arrays.
#
class CommonModulesUtility

  # Populates $external_common_modules_target_root, then sets merged
  # $common_sql_paths / $common_data_paths from internal paths and external target paths.
  # With --flags clean: clones each modules-file repo at its git_reference.
  # Without clean: copies from the parent of the product git root (sibling checkouts).
  def self.materialize_external_common_modules!(logger = nil)
    # Initialize vars if not defined yet
    $internal_common_sql_paths = [] if $internal_common_sql_paths.nil? || !$internal_common_sql_paths.is_a?(Array)
    $internal_common_data_paths = [] if $internal_common_data_paths.nil? || !$internal_common_data_paths.is_a?(Array)
    $common_module_versions = [] if $common_module_versions.nil? || !$common_module_versions.is_a?(Array)

    $external_common_modules_target_root = Globals.external_common_modules_target_root_path
    FileUtils.mkdir_p($external_common_modules_target_root)

    clean_build = $build_flags.include?(:clean)

    # Dev builds need a local checkout tree to copy from (siblings of the product repo).
    if !$common_module_versions.empty? && !clean_build then
      resolve_external_common_modules_source_root!
    end

    external_sql_paths = []
    external_data_paths = []

    # Populate target dirs
    deduped_entries($common_module_versions).each do |entry|
      repo_url = entry.fetch('git_repository')
      repo_key = repo_folder_basename(repo_url)
      target_dir = File.join($external_common_modules_target_root, repo_key).fix_pathname.chomp('/')

      populate_target_dir!(target_dir, repo_url, entry['git_reference'], clean_build, logger)

      sql_path = entry['sql_path']
      data_path = entry['data_path']
      raise "External modules entry for '#{repo_url}' missing 'sql_path'" if sql_path.nil? || sql_path.to_s.empty?
      raise "External modules entry for '#{repo_url}' missing 'data_path'" if data_path.nil? || data_path.to_s.empty?

      external_sql_paths << File.join(target_dir, sql_path).fix_pathname.chomp('/')
      external_data_paths << File.join(target_dir, data_path).fix_pathname.chomp('/')
    end

    # Set merged paths
    $common_sql_paths = ($internal_common_sql_paths + external_sql_paths).map { |path| path.fix_pathname.chomp('/') }
    $common_data_paths = ($internal_common_data_paths + external_data_paths).map { |path| path.fix_pathname.chomp('/') }
    validate_materialized_paths!(external_sql_paths, external_data_paths)

    unless logger.nil? then
      logger.writeln "External common modules target: #{$external_common_modules_target_root}"
      external_sql_paths.each { |path| logger.writeln "  common sql:  #{path}" }
      external_data_paths.each { |path| logger.writeln "  common data: #{path}" }
    end
  end

  # Build JSON { "common_module_repos": [ { repo_url, commit_hash, sql_paths, data_paths, had_uncommitted_changes }, ... ] } from common_sql_paths and common_data_paths. One entry per repo; paths are in sql_paths and data_paths arrays.
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

  # Returns array of entry hashes (repo_url, commit_hash, sql_paths, data_paths, had_uncommitted_changes), one per unique repo. Paths not in a git repo are skipped. Order: by repo_url, then commit_hash.
  def self.build_common_module_repos(common_sql_paths, common_data_paths)
    groups = {}
    add_paths_to_groups(groups, common_sql_paths, :sql)
    add_paths_to_groups(groups, common_data_paths, :data)
    entries = groups.each_value.map { |g| entry(g[:repo_url], g[:hash], g[:sql_paths], g[:data_paths], g[:dirty]) }
    return entries.sort_by { |e| [e['repo_url'], e['commit_hash']] }
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

  # Builds one common_module_repos entry hash for the JSON. Normalizes nil repo_url/commit_hash to ''.
  def self.entry(repo_url, hash, sql_paths, data_paths, had_uncommitted_changes)
    return {
      'repo_url' => (repo_url || '').to_s,
      'commit_hash' => (hash || '').to_s,
      'sql_paths' => sql_paths,
      'data_paths' => data_paths,
      'had_uncommitted_changes' => had_uncommitted_changes
    }
  end

  # Ensures each modules-file git_repository appears at most once; raises on duplicates.
  # Also requires plain HTTPS URLs (no SSH / embedded credentials).
  def self.deduped_entries(entries)
    seen = {}
    entries.each do |entry|
      repo = entry.fetch('git_repository')
      GitUtility.require_plain_https_repo_url!(repo)
      raise "Duplicate external modules entry for git_repository '#{repo}'" if seen.key?(repo)
      seen[repo] = entry
    end
    return seen.values
  end

  # Returns external sql and data path arrays under an already-populated target_root
  # from versions entries (no clone/copy). Used when restoring a previous prepare.
  def self.build_external_paths_from_target(target_root, versions)
    external_sql_paths = []
    external_data_paths = []
    deduped_entries(versions).each do |entry|
      repo_url = entry.fetch('git_repository')
      repo_key = repo_folder_basename(repo_url)
      target_dir = File.join(target_root, repo_key).fix_pathname.chomp('/')
      sql_path = entry['sql_path']
      data_path = entry['data_path']
      raise "External modules entry for '#{repo_url}' missing 'sql_path'" if sql_path.nil? || sql_path.to_s.empty?
      raise "External modules entry for '#{repo_url}' missing 'data_path'" if data_path.nil? || data_path.to_s.empty?
      external_sql_paths << File.join(target_dir, sql_path).fix_pathname.chomp('/')
      external_data_paths << File.join(target_dir, data_path).fix_pathname.chomp('/')
    end
    return external_sql_paths, external_data_paths
  end

  # Parent of the product git root: external repos are siblings of the product checkout.
  def self.resolve_external_common_modules_source_root!
    product_root = GitUtility.get_git_repo_root($product_sql_path)
    raise "Cannot derive external common modules source root: product SQL path is not in a git repository ($product_sql_path = \"#{$product_sql_path}\")" if product_root.nil? || product_root.to_s.empty?
    $external_common_modules_source_root = File.expand_path(File.join(product_root, '..')).fix_pathname
    raise "External common modules source root not found ($external_common_modules_source_root = \"#{$external_common_modules_source_root}\")" unless File.directory?($external_common_modules_source_root)
  end

  # Folder name under the external modules target/source root (repo basename without .git).
  def self.repo_folder_basename(repo_url)
    return repo_url.to_s.sub(%r{/$}, '').sub(%r{\.git$}i, '').split('/').last
  end

  # Fills target_dir for one external module: git clone+checkout when clean_build,
  # otherwise copy from $external_common_modules_source_root/<repo>/ (excluding gitignored files).
  def self.populate_target_dir!(target_dir, repo_url, gitref, clean_build, logger)
    if clean_build then
      # Reproducible path: clone at the pinned git_reference from the modules file.
      raise "External modules entry for '#{repo_url}' missing 'git_reference'" if gitref.nil? || gitref.to_s.empty?
      if File.directory?(target_dir) && GitUtility.ref_matches_path?(target_dir, gitref) then
        logger.writeln "Reusing existing clone at '#{target_dir}' (#{gitref})" unless logger.nil?
        return
      end
      if File.directory?(target_dir) then
        logger.writeln "Removing stale clone at '#{target_dir}'..." unless logger.nil?
        FileUtils.rm_rf(target_dir)
      end
      logger.writeln "Cloning '#{repo_url}' to '#{target_dir}' @ #{gitref}" unless logger.nil?
      GitUtility.clone_and_checkout(repo_url, target_dir, gitref)
    else
      # Normal local path: copy working trees from the configured source root (skip gitignored files).
      repo_key = repo_folder_basename(repo_url)
      source_dir = File.join($external_common_modules_source_root, repo_key).fix_pathname.chomp('/')
      raise "External common module source not found (#{repo_key} = \"#{source_dir}\")" unless File.directory?(source_dir)

      if !File.directory?(target_dir) || source_newer_than_target?(source_dir, target_dir) then
        logger.writeln "Copying '#{source_dir}' to '#{target_dir}' (excluding gitignored files)" unless logger.nil?
        FileUtils.rm_rf(target_dir) if File.directory?(target_dir)
        FileUtils.mkdir_p(File.dirname(target_dir))
        GitUtility.copy_working_tree_excluding_ignored(source_dir, target_dir)
      else
        logger.writeln "Reusing existing copy at '#{target_dir}'" unless logger.nil?
      end
    end
  end

  # True when source_dir is newer than target_dir (by directory mtime), so a re-copy is needed.
  def self.source_newer_than_target?(source_dir, target_dir)
    return true unless File.directory?(target_dir)
    return File.mtime(target_dir) < File.mtime(source_dir)
  end

  # Raises unless every materialized external sql/data path exists as a directory.
  def self.validate_materialized_paths!(sql_paths, data_paths)
    sql_paths.each_with_index { |path, idx|
      raise "External common SQL path not found (#{idx}: \"#{path}\")" unless File.directory?(path)
    }
    data_paths.each_with_index { |path, idx|
      raise "External common data path not found (#{idx}: \"#{path}\")" unless File.directory?(path)
    }
  end

  private_class_method :build_common_module_repos, :add_paths_to_groups, :path_repo_info, :entry,
                       :deduped_entries, :populate_target_dir!, :source_newer_than_target?,
                       :resolve_external_common_modules_source_root!
end
