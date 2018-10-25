#!/usr/bin/env ruby

# List all data files that could not be located in the 'org' folder of the FTP server.
# This is undesired because then it is difficult to know where these files comes from.

this_path = File.expand_path(File.dirname(__FILE__)) # This makes sure we can 'require' from current folder in all Ruby versions.
$LOAD_PATH << this_path unless $LOAD_PATH.include?(this_path)
$LOAD_PATH.delete('.') if $LOAD_PATH.include?('.')

require 'fileutils'
require 'getoptlong'

require 'Utility.rb'
require 'DataSourceCollector.rb'

# Settings
require 'Globals.rb'
Globals.load_settings(ARGV.size > 0 ? ARGV[0] : nil)

# Logger
require 'BuildLogger.rb'
$logger = BuildLogger.new
$logger.open($product_log_path, 'missing_org')

# Parses the load-SQL files to see which files in the db-data folder are used.
# Copies these files to your local db-data folder.

# Collect datasources
$logger.writeln "Collecting datasources..."
$datasources = DataSourceCollector.collect($logger, $product_data_path, $common_data_path, nil).keys.sort

# FTP connect
$ftp_org_path = $sftp_data_path.fix_pathname + $org_dir.fix_pathname
$logger.writeln "Connecting to SFTP (#{$ftp_org_path})..."

require 'SFTPUploader.rb'

if /^(sftp\:\/\/)?([^\/:]+)(\:(\d+))?(\/.*)?$/i.match($ftp_org_path) then
  sftp_data_host = $2
  sftp_data_port = ($4 || 22).to_i
  sftp_data_remote_path = $5 || ''
  $logger.error 'Specify $sftp_data_readonly_username and $sftp_data_readonly_password in ..\UserSettings.rb' if $sftp_data_readonly_username == 'REDACTED' || $sftp_data_readonly_password == 'REDACTED'
else
  $logger.error "Not a valid SFTP location: #{$ftp_org_path}"
end
$fs = SFTPUploader.new($logger)

# Collect FTP files
$logger.writeln "Scanning SFTP for .txt files..."
$fs.connect sftp_data_host, sftp_data_port, $sftp_data_readonly_username, $sftp_data_readonly_password, sftp_data_remote_path
remote_txt_files = $fs.get_filenames($fs.getdir, '**/*.txt')
$logger.writeln "#{remote_txt_files.size} files found."

# Map it
$datasource_map = {}
remote_txt_files.each { |txt_file|
  txt_file.downcase!
  $datasource_map[File.basename(txt_file)] = txt_file
}

# List results
$logger.writeln "\nThese files could be found in org:"
$datasources.each { |datasource|
  datasource_filename = File.basename(datasource).downcase
  $logger.writeln $datasource_map[datasource_filename] if $datasource_map.has_key?(datasource_filename)
}

$logger.writeln "\nThe following files are NOT found in org:"
$datasources.each { |datasource|
  datasource_filename = File.basename(datasource).downcase
  $logger.writeln datasource unless $datasource_map.has_key?(datasource_filename)
}
