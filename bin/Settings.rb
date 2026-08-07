#
# Default settings. Override in product settings, AppSettings.rb, or UserSettings.rb
#

# Set up default paths from root
$target_path = File.expand_path('./target/') if $target_path.nil?          # Default /<working dir>/target
$log_path = File.expand_path($target_path + '/log/').fix_pathname          # /<target_path>/log/
$output_path = File.expand_path($target_path + '/build/').fix_pathname     # /<target_path>/build/
$temp_path = File.expand_path($target_path + '/temp/').fix_pathname        # /<target_path>/temp/

# PostgreSQL
$pg_username = 'aerius' # Override in UserSettings.rb if needed
$pg_password = 'aerius' # Override in UserSettings.rb if needed

unless ENV['POSTGRESQL_BIN'].nil? then
  $pg_bin_path = ENV['POSTGRESQL_BIN']
else
  if ON_WINDOWS then
    if !ENV['CommonProgramW6432'].nil? then # ENV['ProgramFiles'] gives incorrect result, namely equal to ENV['ProgramFiles(x86)']
      $pg_bin_path = Utility.find_best_postgresql_path(File.expand_path(ENV['CommonProgramW6432'] + '/../'))
    elsif !ENV['ProgramFiles(x86)'].nil? then
      $pg_bin_path = Utility.find_best_postgresql_path(ENV['ProgramFiles(x86)'])
    elsif !ENV['ProgramFiles'].nil? then
      $pg_bin_path = Utility.find_best_postgresql_path(ENV['ProgramFiles'])
    end
  else # Linux
    $pg_bin_path = ''  # assume it's in the shell path
  end
end

$database_template = 'template0'
$database_tablespace = ''
$database_collation = '' # Can override in ..\AppSettings.rb in case you need to force it, otherwise it is taken from the template

$database_name_prefix = PathConventions::DEFAULT_DATABASE_NAME_PREFIX if $database_name_prefix.nil?

$db_essentials_function_prefix = 'system.'
$db_unittest_prefix = 'unittest_'

# Git
$git_bin_path = GitUtility.default_bin_path

# HTTPS for syncing data files — set $https_data_path (full remote dbdata URL) in AppSettings.rb;
# set $https_data_username / $https_data_password in UserSettings.rb when needed.

# Maximum number of simultaneous connections in multithread blocks
$max_threads = 10

# Behaviour when uncommitted/untracked changes are detected: :warn, :prompt, or :abort
$on_uncommitted_changes = :warn

# Show all hints by default
HINT_LEVEL_OFF = 0
HINT_LEVEL_MAJOR = 1
HINT_LEVEL_ALL = 2
$hint_level = HINT_LEVEL_ALL
