require 'Utility.rb'
require 'PathConventions.rb'
require 'GitUtility.rb'

# Initialize all globals

$runscript_file = nil
$product_settings_file = nil

$build_flags = []
$dump_filetitle = nil

##
# Class with a load-methods
#
class Globals

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

  # Normalize path and raise unless it exists as a directory.
  def self.ensure_dir!(path, label)
    path = path.fix_pathname
    raise "#{label} not found (#{label} = \"#{path}\")" unless File.exist?(path) && File.directory?(path)
    path
  end

  # Load buildsystem, product, project and user settings
  def self.load_settings(product_settings_file_argument)

    # Load buildsystem default settings
    require 'Settings.rb'

    # Load product override settings (mandatory)
    determine_product_settings_file(product_settings_file_argument)
    require $product_settings_file

    raise "Product not set ($product)" if $product.nil?
    raise "Source path not set ($source_path)" if $source_path.nil?
    raise "Build config path not set ($build_config_path)" if $build_config_path.nil?

    # Resolve relative paths against the product settings directory
    product_settings_dir = File.dirname($product_settings_file)
    $source_path = PathConventions.expand_from(product_settings_dir, $source_path)
    $build_config_path = ensure_dir!(PathConventions.expand_from(product_settings_dir, $build_config_path), '$build_config_path')

    # Load AppSettings / UserSettings from build-config/config/
    $app_settings_file = PathConventions.join($build_config_path, PathConventions::CONFIG_DIR, PathConventions::APP_SETTINGS_FILE).fix_filename
    raise "AppSettings file '#{$app_settings_file}' not found" unless (File.exist?($app_settings_file) && !File.directory?($app_settings_file))
    require $app_settings_file

    $user_settings_file = PathConventions.join($build_config_path, PathConventions::CONFIG_DIR, PathConventions::USER_SETTINGS_FILE).fix_filename
    $user_settings_file = nil unless File.exist?($user_settings_file)
    require $user_settings_file unless $user_settings_file.nil?

    # Fixed paths from convention
    $source_path = ensure_dir!($source_path, '$source_path')

    $product_sql_path = ensure_dir!(PathConventions.join($source_path, PathConventions::SQL_REL, $product.to_s), '$product_sql_path')
    $product_data_path = ensure_dir!(PathConventions.join($source_path, PathConventions::DATA_REL, $product.to_s), '$product_data_path')

    $common_sql_paths = [
      PathConventions.dir_if_exists($source_path, PathConventions::SQL_REL, PathConventions::COMMON_DIR),
      PathConventions.dir_if_exists(PathConventions.workspace_root, PathConventions::MODULES_REPO, PathConventions::MODULES_SQL_REL),
      PathConventions.join(PathConventions.database_build_root, PathConventions::BUILTIN_COMMON_SQL_REL).fix_pathname
    ].compact
    $common_sql_paths.map!.with_index { |common_sql_path, idx|
      ensure_dir!(common_sql_path, "$common_sql_paths[#{idx}]")
    }

    $common_data_paths = [
      PathConventions.dir_if_exists($source_path, PathConventions::DATA_REL, PathConventions::COMMON_DIR),
      PathConventions.dir_if_exists(PathConventions.workspace_root, PathConventions::MODULES_REPO, PathConventions::MODULES_DATA_REL)
    ].compact
    $common_data_paths.map!.with_index { |common_data_path, idx|
      ensure_dir!(common_data_path, "$common_data_paths[#{idx}]")
    }

    $runscripts_path = ensure_dir!(PathConventions.join($build_config_path, PathConventions::SCRIPTS_DIR), '$runscripts_path')

    # Overridable defaults
    $dbdata_path = PathConventions.join(PathConventions.workspace_root, PathConventions::DBDATA_DIR) if $dbdata_path.nil?
    $dbdata_path = ensure_dir!($dbdata_path, '$dbdata_path')

    raise "Temp path not set ($temp_path)" if $temp_path.nil?
    raise "Output path not set ($output_path)" if $output_path.nil?
    raise "Log path not set ($log_path)" if $log_path.nil?

    $temp_path = $temp_path.fix_pathname
    $output_path = $output_path.fix_pathname
    $log_path = $log_path.fix_pathname

    raise 'Database name prefix not set ($database_name_prefix)' if $database_name_prefix.nil?
    raise 'PostgreSQL bin path not set ($pg_bin_path)' if $pg_bin_path.nil?
    raise "PostgreSQL bin path not found ($pg_bin_path = \"#{$pg_bin_path}\")" unless ((File.exist?($pg_bin_path) && File.directory?($pg_bin_path)) || (!ON_WINDOWS && $pg_bin_path.empty?))
    raise "PostgreSQL username not set ($pg_username)" if $pg_username.nil? || $pg_username.to_s.empty?
    raise "PostgreSQL password not set ($pg_password)" if $pg_password.nil? || $pg_password.to_s.empty?
    $pg_bin_path = $pg_bin_path.fix_pathname unless $pg_bin_path.empty?
    $git_bin_path = $git_bin_path.fix_pathname unless ($git_bin_path.nil? || $git_bin_path.empty?)
  end

 private

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
