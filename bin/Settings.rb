#
# Default settings. Can optionally override in ..\AppSettings.rb and ..\UserSettings.rb
#

# Set up default paths from root
$target_path = File.expand_path('./target/') if $target_path.nil?          # Default /<working dir>/target
$log_path = File.expand_path($target_path + '/log/').fix_pathname          # /<target_path>/log/
$output_path = File.expand_path($target_path + '/build/').fix_pathname     # /<target_path>/build/
$temp_path = File.expand_path($target_path + '/temp/').fix_pathname        # /<target_path>/temp/

# PostgreSQL
$pg_username = 'REDACTED' # Override in ..\UserSettings.rb
$pg_password = 'REDACTED' # Override in ..\UserSettings.rb

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

#$database_name_prefix = '...' # Override in ..\AppSettings.rb
#$db_function_prefix = '...' # Override in ..\AppSettings.rb

$on_build_server = false

# Datasource files .. relative paths on the FTP
$dbdata_dir = 'db-data/'
$org_dir = 'org/'

# VCS
$vcs = nil  # :git or :svn
# Git
unless ENV['GIT_BIN'].nil? then
  $git_bin_path = ENV['GIT_BIN']
else
  if ON_WINDOWS then
    $git_bin_path = ENV['ProgramFiles(x86)'].fix_pathname + 'Git/cmd/' unless ENV['ProgramFiles(x86)'].nil?
    $git_bin_path = ENV['ProgramFiles'].fix_pathname + 'Git/cmd/' if $git_bin_path.nil? && !ENV['ProgramFiles'].nil?
    $git_bin_path = '' if $git_bin_path.nil?  # assume it's in the shell path
  else # Linux
    $git_bin_path = ''  # assume it's in the shell path
  end
end
# SVN
unless ENV['SVN_BIN'].nil? then
  $svn_bin_path = ENV['SVN_BIN']
else
  $svn_bin_path = ''  # assume it's in the shell path
end
#$svn_root_url = 'https://repository...' # Override in ..\AppSettings.rb

# SFTP for syncing data files
$sftp_data_path = 'sftp://a.b.c/xyz' # Override in ..\AppSettings.rb
$sftp_data_readonly_username = 'REDACTED' # Override in ..\UserSettings.rb
$sftp_data_readonly_password = 'REDACTED' # Override in ..\UserSettings.rb
$sftp_data_username = 'REDACTED' # Override in ..\UserSettings.rb
$sftp_data_password = 'REDACTED' # Override in ..\UserSettings.rb
# or FTP
$ftp_data_path = 'ftp://a.b.c/xyz/' # Override in ..\AppSettings.rb
$ftp_data_username = 'REDACTED' # Override in ..\UserSettings.rb
$ftp_data_password = 'REDACTED' # Override in ..\UserSettings.rb

# Maximum number of simultaneous connections in multithread blocks
$max_threads = 10

# Show all hints by default
HINT_LEVEL_OFF = 0
HINT_LEVEL_MAJOR = 1
HINT_LEVEL_ALL = 2
$hint_level = HINT_LEVEL_ALL
