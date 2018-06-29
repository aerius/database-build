require 'Utility.rb'

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
  
  # Load buildsystem, product, project and user settings
  def self.load_settings(product_settings_file_argument)

    # Load buildsystem default settings
    require 'Settings.rb'
    
    # Load product override settings (mandatory)
    determine_product_settings_file(product_settings_file_argument)
    #raise 'Product settings file unknown.' if $product_settings_file.nil?  # Code forgot to call Globals.determine_product_settings_file first.
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
    raise "Common SQL path not set ($common_sql_path)" if $common_sql_path.nil?
    raise "Common SQL path not found ($common_sql_path = \"#{$common_sql_path}\")" unless (File.exist?($common_sql_path) && File.directory?($common_sql_path))
    raise "Product data path not set ($product_data_path)" if $product_data_path.nil?
    raise "Product data path not found ($product_data_path = \"#{$product_data_path}\")" unless (File.exist?($product_data_path) && File.directory?($product_data_path))
    raise "Common data path not set ($common_data_path)" if $common_data_path.nil?
    raise "Common data path not found ($common_data_path = \"#{$common_data_path}\")" unless (File.exist?($common_data_path) && File.directory?($common_data_path))
    raise "Temp path not set ($temp_path)" if $temp_path.nil?
    raise "Output path not set ($output_path)" if $output_path.nil?
    raise "Log path not set ($log_path)" if $log_path.nil?
    raise "Datasource path not set ($dbdata_path)" if $dbdata_path.nil?
    raise "Datasource path not found ($dbdata_path = \"#{$dbdata_path}\")" unless (File.exist?($dbdata_path) && File.directory?($dbdata_path))
    raise "Runscripts path not found ($runscripts_path = \"#{$runscripts_path}\")" unless $runscripts_path.nil? || (File.exist?($runscripts_path) && File.directory?($runscripts_path))

    $product_sql_path = $product_sql_path.fix_pathname
    $common_sql_path = $common_sql_path.fix_pathname
    $product_data_path = $product_data_path.fix_pathname
    $common_data_path = $common_data_path.fix_pathname
    $dbdata_path = $dbdata_path.fix_pathname
    $runscripts_path = $runscripts_path.fix_pathname unless $runscripts_path.nil?    

    $temp_path = $temp_path.fix_pathname
    $output_path = $output_path.fix_pathname
    $log_path = $log_path.fix_pathname
    $product_temp_path = $temp_path if $product_temp_path.nil?       # /database/target/
    $product_output_path = $output_path if $product_output_path.nil? # /database/target/build/
    $product_log_path = $log_path if $product_log_path.nil?          # /database/target/log/

    # Standalone paths and settings
    raise 'Database name prefix not set ($database_name_prefix)' if $database_name_prefix.nil?
    raise 'Database function prefix not set ($db_function_prefix)' if $db_function_prefix.nil?
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