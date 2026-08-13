require 'fileutils'
require 'GitUtility.rb'
require 'PathConventions.rb'

##
# Materialize pinned external common modules under output.target_path/<TARGET_DIRNAME>/.
# Dev builds copy sibling checkouts; --flags clean clones each git_reference.
#
class ExternalModules

  TARGET_DIRNAME = 'externals'

  # Materialize externals and merge paths into $build_config.
  def self.prepare(logger = nil)
    materialize(logger)
  end

  #
  # Private section
  #
  private

  # Clone or copy each modules-file entry into the target tree, then apply merged common paths.
  def self.materialize(logger = nil)
    clean_build = $build_config.session.build_flags.include?(:clean)
    versions = Array($build_config.session.common_module_versions)
    target_root = resolve_target_root_path
    
    external_sql_paths = []
    external_data_paths = []

    # Create target directory
    FileUtils.mkdir_p(target_root)

    # Resolve source root for dev builds
    source_root = nil
    if !versions.empty? && !clean_build then
      source_root = resolve_source_root
    end

    # Materialize each entry
    deduped_entries(versions).each do |entry|
      repo_url = entry.fetch('git_repository')
      repo_key = repo_folder_basename(repo_url)

      target_dir = File.join(target_root, repo_key).fix_pathname.chomp('/')

      populate_target_dir(target_dir, repo_url, entry['git_reference'], clean_build, source_root, logger)

      external_sql_paths << File.join(target_dir, PathConventions::EXTERNAL_MODULES_SQL_REL).fix_pathname.chomp('/')
      external_data_paths << File.join(target_dir, PathConventions::EXTERNAL_MODULES_DATA_REL).fix_pathname.chomp('/')
    end

    require_materialized_paths(external_sql_paths, external_data_paths)
    $build_config.apply_common_module_paths(external_sql_paths, external_data_paths)

    unless logger.nil? then
      logger.writeln "Prepared common modules at #{target_root}"
      external_sql_paths.each { |path| logger.writeln "  common sql:  #{path}" }
      external_data_paths.each { |path| logger.writeln "  common data: #{path}" }
    end
  end

  def self.resolve_target_root_path
    return File.expand_path(File.join($build_config.output.target_path, TARGET_DIRNAME)).fix_pathname
  end

  # Parent of the product git root: external repos are siblings of the product checkout.
  def self.resolve_source_root
    product_sql = $build_config.layout.product_sql_path
    product_root = GitUtility.get_git_repo_root(product_sql)
    raise "Cannot derive external common modules source root: product SQL path is not in a git repository (product_sql_path = \"#{product_sql}\")" if product_root.nil? || product_root.to_s.empty?
    source_root = File.expand_path(File.join(product_root, '..')).fix_pathname
    raise "External common modules source root not found (\"#{source_root}\")" unless File.directory?(source_root)
    return source_root
  end

  def self.deduped_entries(entries)
    seen = {}
    entries.each do |entry|
      repo = entry.fetch('git_repository')
      GitUtility.require_plain_https_repo_url(repo)
      if entry.key?('sql_path') || entry.key?('data_path') then
        raise "External modules entry for '#{repo}' must not set sql_path/data_path; layout is fixed (#{PathConventions::EXTERNAL_MODULES_SQL_REL} / #{PathConventions::EXTERNAL_MODULES_DATA_REL})"
      end
      raise "Duplicate external modules entry for git_repository '#{repo}'" if seen.key?(repo)
      seen[repo] = entry
    end
    return seen.values
  end

  # Extract the basename of a repository URL
  def self.repo_folder_basename(repo_url)
    return repo_url.to_s.sub(%r{/$}, '').sub(%r{\.git$}i, '').split('/').last
  end

  def self.populate_target_dir(target_dir, repo_url, gitref, clean_build, source_root, logger)
    if clean_build then
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
      repo_key = repo_folder_basename(repo_url)
      source_dir = File.join(source_root, repo_key).fix_pathname.chomp('/')
      raise "External common module source not found (#{repo_key} = \"#{source_dir}\")" unless File.directory?(source_dir)

      logger.writeln "Copying '#{source_dir}' to '#{target_dir}'" unless logger.nil?
      FileUtils.rm_rf(target_dir) if File.exist?(target_dir)
      FileUtils.mkdir_p(File.dirname(target_dir))
      FileUtils.cp_r(source_dir, target_dir)
    end
  end

  def self.require_materialized_paths(sql_paths, data_paths)
    sql_paths.each_with_index { |path, idx|
      raise "External common SQL path not found (#{idx}: \"#{path}\")" unless File.directory?(path)
    }
    data_paths.each_with_index { |path, idx|
      raise "External common data path not found (#{idx}: \"#{path}\")" unless File.directory?(path)
    }
  end

end
