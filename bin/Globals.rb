require 'json'
require 'fileutils'
require 'Utility.rb'

# Directory name under $target_path for materialized external common modules.
EXTERNAL_COMMON_MODULES_TARGET_DIRNAME = 'externals'

# Initialize all globals

$runscript_file = nil
$product_settings_file = nil

$build_flags = []
$dump_filetitle = nil

# External common modules: product settings only list in-repo paths; optional $external_common_modules_file lists external repos.
$external_common_modules_file = nil # Path to the external common modules file
$common_module_versions = nil # List of external common module versions from $external_common_modules_file
$internal_common_sql_paths = nil # In-repo common SQL paths
$internal_common_data_paths = nil # In-repo common SQL and data paths

$external_common_modules_source_root = nil # Derived from product git root during prepare
$external_common_modules_target_root = nil # Set to $target_path/EXTERNAL_COMMON_MODULES_TARGET_DIRNAME during prepare

##
# Class with a load-methods
#
class Globals

  # Load settings, apply build flags, materialize or restore common module paths (idempotent).
  def self.prepare!(product_settings_file_argument, logger: nil)
    load_config(product_settings_file_argument)
    if prepared_state_valid? then
      restore_common_module_paths!(logger)
    else
      finalize_common_module_paths!(logger)
      write_prepared_marker!
    end
  end

  # Determine full runscript filename. First absolute path or relative to CWD. Otherwise see if $runscripts_path is set and use that.
  def self.determine_runscript_file(runscript_file_argument)
    if runscript_file_argument.nil? then
      puts 'Specify a runscript. See --help for more information.'
      exit
    else
      $runscript_file = File.expand_path(runscript_file_argument).fix_filename
      $runscript_file += '.rb' if !File.exist?($runscript_file) && File.exist?($runscript_file + '.rb')

      unless (File.exist?($runscript_file) && !File.directory?($runscript_file)) || $runscripts_path.nil? then
        $runscript_file = ($runscripts_path + runscript_file_argument).fix_filename
        $runscript_file += '.rb' if !File.exist?($runscript_file) && File.exist?($runscript_file + '.rb')
      end

      raise "Runscript '#{$runscript_file}' not found." unless (File.exist?($runscript_file) && !File.directory?($runscript_file))
    end
  end

  # Parse a comma-separated --flags value into unique symbols on $build_flags (e.g. clean).
  def self.add_build_flags(flags_argument)
    return if flags_argument.nil?
    flags_argument.split(',').each { |flag|
      sym = flag.strip.downcase.to_sym
      $build_flags << sym unless $build_flags.include?(sym)
    }
  end

 private

  # Load buildsystem, product, project and user settings; optionally load $external_common_modules_file.
  # Does not materialize common module paths.
  def self.load_config(product_settings_file_argument)

    # Load buildsystem default settings
    require 'Settings.rb'

    # Derived globals from a previous prepare! in the same process must not affect validation.
    $common_sql_paths = nil
    $common_data_paths = nil
    $internal_common_sql_paths = nil
    $internal_common_data_paths = nil
    $external_common_modules_source_root = nil
    $external_common_modules_file = nil
    $common_module_versions = nil
    $versions_file = nil # Detect legacy product settings

    # Load product override settings (mandatory)
    determine_product_settings_file(product_settings_file_argument)
    require $product_settings_file
    $user_product_settings_file = File.dirname($product_settings_file).fix_pathname + File.basename($product_settings_file, '.rb') + '.User.rb'
    $user_product_settings_file = nil unless File.exist?($user_product_settings_file)
    require $user_product_settings_file unless $user_product_settings_file.nil?

    # Load project override settings (if specified)
    if $project_settings_file.nil? then
      puts 'WARNING: project settings file not set ($project_settings_file)'
    else
      $project_settings_file = File.expand_path($project_settings_file).fix_filename
      $project_settings_file += '.rb' if !File.exist?($project_settings_file) && File.exist?($project_settings_file + '.rb')
      raise "Project settings file '#{$project_settings_file}' not found" unless (File.exist?($project_settings_file) && !File.directory?($project_settings_file))
      require $project_settings_file
      $user_project_settings_file = File.dirname($project_settings_file).fix_pathname + File.basename($project_settings_file, '.rb') + '.User.rb'
      $user_project_settings_file = nil unless File.exist?($user_project_settings_file)
      require $user_project_settings_file unless $user_project_settings_file.nil?
    end

    # Process/validate everything
    raise "Product not set ($product)" if $product.nil?
    raise "Product SQL path not set ($product_sql_path)" if $product_sql_path.nil?
    raise "Product SQL path not found ($product_sql_path = \"#{$product_sql_path}\")" unless (File.exist?($product_sql_path) && File.directory?($product_sql_path))
    raise "Product data path not set ($product_data_path)" if $product_data_path.nil?
    raise "Product data path not found ($product_data_path = \"#{$product_data_path}\")" unless (File.exist?($product_data_path) && File.directory?($product_data_path))
    raise "Temp path not set ($temp_path)" if $temp_path.nil?
    raise "Output path not set ($output_path)" if $output_path.nil?
    raise "Log path not set ($log_path)" if $log_path.nil?
    raise "Datasource path not set ($dbdata_path)" if $dbdata_path.nil?
    raise "Datasource path not found ($dbdata_path = \"#{$dbdata_path}\")" unless (File.exist?($dbdata_path) && File.directory?($dbdata_path))
    raise "Runscripts path not found ($runscripts_path = \"#{$runscripts_path}\")" unless $runscripts_path.nil? || (File.exist?($runscripts_path) && File.directory?($runscripts_path))

    reject_legacy_common_path_settings!
    unless $versions_file.nil? || $versions_file.to_s.empty? then
      raise 'Use $external_common_modules_file instead of $versions_file'
    end
    unless $external_common_modules_source_root.nil? then
      raise 'Do not set $external_common_modules_source_root; it is derived as the parent of the product git repository root'
    end

    $internal_common_sql_paths = [] if $internal_common_sql_paths.nil? || !$internal_common_sql_paths.is_a?(Array)
    $internal_common_data_paths = [] if $internal_common_data_paths.nil? || !$internal_common_data_paths.is_a?(Array)
    $internal_common_sql_paths.each_with_index { |internal_common_sql_path, idx|
      raise "Internal common SQL path not found ($internal_common_sql_paths[#{idx}] = \"#{internal_common_sql_path}\")" unless (File.exist?(internal_common_sql_path) && File.directory?(internal_common_sql_path))
    }
    $internal_common_data_paths.each_with_index { |internal_common_data_path, idx|
      raise "Internal common data path not found ($internal_common_data_paths[#{idx}] = \"#{internal_common_data_path}\")" unless (File.exist?(internal_common_data_path) && File.directory?(internal_common_data_path))
    }

    load_external_common_modules_file!

    $product_sql_path = $product_sql_path.fix_pathname
    $product_data_path = $product_data_path.fix_pathname
    $dbdata_path = $dbdata_path.fix_pathname
    $runscripts_path = $runscripts_path.fix_pathname unless $runscripts_path.nil?
    $internal_common_sql_paths.map! { |internal_common_sql_path| internal_common_sql_path.fix_pathname }
    $internal_common_data_paths.map! { |internal_common_data_path| internal_common_data_path.fix_pathname }

    $temp_path = $temp_path.fix_pathname
    $output_path = $output_path.fix_pathname
    $log_path = $log_path.fix_pathname
    $product_temp_path = $temp_path if $product_temp_path.nil?
    $product_output_path = $output_path if $product_output_path.nil?
    $product_log_path = $log_path if $product_log_path.nil?

    # Standalone paths and settings
    raise 'Database name prefix not set ($database_name_prefix)' if $database_name_prefix.nil?
    raise 'PostgreSQL bin path not set ($pg_bin_path)' if $pg_bin_path.nil?
    raise "PostgreSQL bin path not found ($pg_bin_path = \"#{$pg_bin_path}\")" unless ((File.exist?($pg_bin_path) && File.directory?($pg_bin_path)) || (!ON_WINDOWS && $pg_bin_path.empty?))
    raise "PostgreSQL username not set ($pg_username)" if $pg_username.nil?
    raise 'Override PostgreSQL username ($pg_username) in user project settings' if $pg_username == 'REDACTED'
    raise 'PostgreSQL password not set ($pg_password)' if $pg_password.nil?
    raise 'Override PostgreSQL password ($pg_password) in user project settings' if $pg_password == 'REDACTED'
    $pg_bin_path = $pg_bin_path.fix_pathname unless $pg_bin_path.empty?
    $git_bin_path = $git_bin_path.fix_pathname unless ($git_bin_path.nil? || $git_bin_path.empty?)
    $svn_bin_path = $svn_bin_path.fix_pathname unless ($svn_bin_path.nil? || $svn_bin_path.empty?)
    $vcs = :svn if $vcs.nil? && !($svn_root_url.nil? || $svn_root_url.empty? || $git_bin_path.nil?)
    $vcs = :git if $vcs.nil? && !$git_bin_path.nil?
  end

  # Materialize external common modules (clone or copy) and set merged $common_sql_paths / $common_data_paths.
  def self.finalize_common_module_paths!(logger = nil)
    require 'CommonModulesUtility.rb'
    CommonModulesUtility.materialize_external_common_modules!(logger)
    assign_merged_common_module_paths!
    validate_merged_common_module_paths!
    unless logger.nil? then
      logger.writeln "Prepared common modules at #{$external_common_modules_target_root}"
    end
  end

  # Rebuild $common_*_paths from an existing EXTERNAL_COMMON_MODULES_TARGET_DIRNAME tree when the prepare marker still matches.
  def self.restore_common_module_paths!(logger = nil)
    require 'CommonModulesUtility.rb'
    $internal_common_sql_paths = [] if $internal_common_sql_paths.nil? || !$internal_common_sql_paths.is_a?(Array)
    $internal_common_data_paths = [] if $internal_common_data_paths.nil? || !$internal_common_data_paths.is_a?(Array)
    $common_module_versions = [] if $common_module_versions.nil? || !$common_module_versions.is_a?(Array)

    $external_common_modules_target_root = external_common_modules_target_root_path

    external_sql_paths, external_data_paths = CommonModulesUtility.build_external_paths_from_target(
      $external_common_modules_target_root, $common_module_versions)
    CommonModulesUtility.validate_materialized_paths!(external_sql_paths, external_data_paths)

    $common_sql_paths = ($internal_common_sql_paths + external_sql_paths).map { |path| path.fix_pathname.chomp('/') }
    $common_data_paths = ($internal_common_data_paths + external_data_paths).map { |path| path.fix_pathname.chomp('/') }
    assign_merged_common_module_paths!
    validate_merged_common_module_paths!

    unless logger.nil? then
      logger.writeln "Reusing prepared common modules at #{$external_common_modules_target_root}"
    end
  end

  # Append this repo's built-in common SQL and normalize path forms on the merged arrays.
  def self.assign_merged_common_module_paths!
    $common_sql_paths = [] if $common_sql_paths.nil?
    $common_data_paths = [] if $common_data_paths.nil?
    $common_sql_paths << database_build_common_sql_path
    $common_sql_paths.map! { |common_sql_path| common_sql_path.fix_pathname }
    $common_data_paths.map! { |common_data_path| common_data_path.fix_pathname }
  end

  # Raises unless every merged common sql/data path exists as a directory.
  def self.validate_merged_common_module_paths!
    raise "Common SQL path(s) not set ($common_sql_paths)" if $common_sql_paths.nil? || $common_sql_paths.empty?
    $common_sql_paths.each_with_index { |common_sql_path, idx|
      raise "Common SQL path not found ($common_sql_paths[#{idx}] = \"#{common_sql_path}\")" unless (File.exist?(common_sql_path) && File.directory?(common_sql_path))
    }
    $common_data_paths.each_with_index { |common_data_path, idx|
      raise "Common data path not found ($common_data_paths[#{idx}] = \"#{common_data_path}\")" unless (File.exist?(common_data_path) && File.directory?(common_data_path))
    }
  end

  # Absolute path of the materialized external modules directory under $target_path.
  def self.external_common_modules_target_root_path
    return File.expand_path(File.join($target_path, EXTERNAL_COMMON_MODULES_TARGET_DIRNAME)).fix_pathname
  end

  # In-repo common SQL shipped with database-build itself (always on $common_sql_paths).
  def self.database_build_common_sql_path
    return File.expand_path('../common/src/main/sql', File.dirname(__FILE__)).fix_pathname
  end

  # Marker written after a successful prepare so SyncDBData + Build can reuse the same materialization.
  def self.prepared_marker_path
    return File.join(external_common_modules_target_root_path, '.prepared.json').fix_filename
  end

  # Inputs that must match for prepare! to skip re-materializing (settings, flags, modules file, paths).
  def self.build_prepared_fingerprint
    fingerprint = {
      'product_settings_file' => $product_settings_file.to_s,
      'external_common_modules_file' => ($external_common_modules_file || '').to_s,
      'external_common_modules_file_mtime' => ($external_common_modules_file.nil? || $external_common_modules_file.to_s.empty?) ? 0 : File.mtime($external_common_modules_file).to_i,
      'build_flags' => $build_flags.map(&:to_s).sort,
      'internal_common_sql_paths' => $internal_common_sql_paths.map(&:to_s),
      'internal_common_data_paths' => $internal_common_data_paths.map(&:to_s),
      'common_module_versions' => JSON.parse(JSON.generate($common_module_versions))
    }
    # Source root only affects dev (copy) mode; always derive (settings must not set it).
    if !$common_module_versions.empty? && !$build_flags.include?(:clean) then
      require 'GitUtility.rb'
      product_root = GitUtility.get_git_repo_root($product_sql_path)
      raise "Cannot fingerprint external common modules source root: product SQL path is not in a git repository ($product_sql_path = \"#{$product_sql_path}\")" if product_root.nil? || product_root.to_s.empty?
      fingerprint['external_common_modules_source_root'] = File.expand_path(File.join(product_root, '..')).fix_pathname
    end
    return fingerprint
  end

  # True when .prepared.json exists and matches the current fingerprint.
  def self.prepared_state_valid?
    marker_path = prepared_marker_path
    return false unless File.exist?(marker_path)
    stored = JSON.parse(File.read(marker_path))
    return stored == build_prepared_fingerprint
  rescue
    return false
  end

  # Persist the current fingerprint after materializing common modules.
  def self.write_prepared_marker!
    FileUtils.mkdir_p(File.dirname(prepared_marker_path))
    File.write(prepared_marker_path, JSON.pretty_generate(build_prepared_fingerprint))
  end

  # Load optional $external_common_modules_file into $common_module_versions (empty when unset).
  def self.load_external_common_modules_file!
    if $external_common_modules_file.nil? || $external_common_modules_file.to_s.empty? then
      $external_common_modules_file = nil
      $common_module_versions = []
      return
    end
    $external_common_modules_file = resolve_external_common_modules_file
    raise "External common modules file '#{$external_common_modules_file}' not found ($external_common_modules_file)" unless File.exist?($external_common_modules_file)
    require $external_common_modules_file
    $common_module_versions = [] if $common_module_versions.nil? || !$common_module_versions.is_a?(Array)
  end

  # Absolute path for $external_common_modules_file from product settings.
  # Relative paths are resolved against the product settings file directory.
  def self.resolve_external_common_modules_file
    path = $external_common_modules_file.to_s
    unless Pathname.new(path).absolute?
      path = File.expand_path(path, File.dirname($product_settings_file))
    else
      path = File.expand_path(path)
    end
    return path.fix_filename
  end

  # Fail fast if product settings still use the old $common_sql_paths / $common_data_paths API.
  def self.reject_legacy_common_path_settings!
    legacy_set = []
    legacy_set << '$common_sql_paths' if defined?($common_sql_paths) && !$common_sql_paths.nil? && $common_sql_paths.is_a?(Array) && !$common_sql_paths.empty?
    legacy_set << '$common_data_paths' if defined?($common_data_paths) && !$common_data_paths.nil? && $common_data_paths.is_a?(Array) && !$common_data_paths.empty?
    legacy_set << '$common_sql_path' if defined?($common_sql_path) && !$common_sql_path.nil?
    legacy_set << '$common_data_path' if defined?($common_data_path) && !$common_data_path.nil?
    unless legacy_set.empty? then
      raise "Use $internal_common_sql_paths / $internal_common_data_paths in product settings and optional $external_common_modules_file instead of #{legacy_set.join(', ')}"
    end
  end

  def self.determine_product_settings_file(product_settings_file_argument)
    if product_settings_file_argument.nil? || product_settings_file_argument.start_with?('-') then
      puts 'Specify a product-settings file. See --help for more information.'
      exit
    else
      $product_settings_file = File.expand_path(product_settings_file_argument).fix_filename
      $product_settings_file += '.rb' if !File.exist?($product_settings_file) && File.exist?($product_settings_file + '.rb')
      $product_settings_file += 'Settings.rb' if !File.exist?($product_settings_file) && File.exist?($product_settings_file + 'Settings.rb')
      raise "Product settings file '#{$product_settings_file}' not found" unless (File.exist?($product_settings_file) && !File.directory?($product_settings_file))
    end
  end

end
