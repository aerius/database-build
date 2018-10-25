#!/usr/bin/env ruby

this_path = File.expand_path(File.dirname(__FILE__)) # This makes sure we can 'require' from current folder in all Ruby versions.
$LOAD_PATH << this_path unless $LOAD_PATH.include?(this_path)
$LOAD_PATH.delete('.') if $LOAD_PATH.include?('.')

require 'fileutils'
require 'getoptlong'

require 'Utility.rb'
require 'DataSourceCollector.rb'
require 'PostgresTools.rb'

# ------------------------------------

def display_help
  puts "Syntax:\n  ruby #{File.basename(__FILE__)} product-settings-file [parameters]\n\n"
  puts "  product-settings-file"
  puts "                      Path and filename of product settings of product to"
  puts "                      sync datasources for. Contains $product and references to paths of"
  puts "                      project, product data and sql, and common data and sql."
  puts "\nParameters:"
  puts "  -p --path           Path where the to-be-parsed SQL files are located (export of"
  puts "                      database/src/build/scripts/sql). Supply if different from"
  puts "                      default"
  puts "  -f --from-local     Sync from local db-data folder. Supply db-data path if different from default"
  puts "     --from-ftp       Sync from $ftp_data FTP. Supply FTP path if different from default"
  puts "     --from-sftp      Sync from $sftp_data SFTP. Supply SFTP path if different from default"
  puts "  -l --to-local       Sync to local db-data folder. Supply path if different from default"
  puts "  -t --to-ftp         Sync to $ftp_data FTP. Supply FTP path if different from default"
  puts "  -s --to-sftp        Sync to $sftp_data SFTP. Supply SFTP path if different from default"
  puts "  -c --continue       Continue on file not found errors"
  puts "  -i --info           Displays defaults path (does not run)"
  puts "  -h --help           This help"
  puts ""
  exit
end

$opts = {}
GetoptLong.new(
    ['--path', '-p', GetoptLong::REQUIRED_ARGUMENT],
    ['--from-ftp', GetoptLong::OPTIONAL_ARGUMENT],
    ['--from-sftp', GetoptLong::OPTIONAL_ARGUMENT],
    ['--from-local', '-f', GetoptLong::OPTIONAL_ARGUMENT],
    ['--to-ftp', '-t', GetoptLong::OPTIONAL_ARGUMENT],
    ['--to-sftp', '-s', GetoptLong::OPTIONAL_ARGUMENT],
    ['--to-local', '-l', GetoptLong::OPTIONAL_ARGUMENT],
    ['--continue', '-c', GetoptLong::NO_ARGUMENT],
    ['--info', '-i', GetoptLong::NO_ARGUMENT],
    ['--help', '-h', GetoptLong::NO_ARGUMENT]
).each { |option, argument| $opts[option.downcase] = argument }

display_help if $opts.has_key?('--help')

# ------------------------------------

# Settings
require 'Globals.rb'
Globals.load_settings(ARGV.size > 0 ? ARGV[0] : nil)

# Logger
require 'BuildLogger.rb'
$logger = BuildLogger.new
$logger.open($product_log_path, 'sync_dbdata')

# Parses the load-SQL files to see which files in the db-data folder are used.
# Copies these files to your local db-data folder.

$from_local = $dbdata_path
$to_local = $from_local   # deprecated: NAS path = $oti_nas_path.fix_pathname + $dbdata_dir.fix_pathname
$from_ftp = $ftp_data_path.fix_pathname + $dbdata_dir.fix_pathname unless $ftp_data_path.nil?
$to_ftp = $from_ftp
$from_sftp = $sftp_data_path.fix_pathname + $dbdata_dir.fix_pathname
$to_sftp = $from_sftp

# ---------

$source = nil
$target = nil
$source_path = nil
$target_path = nil
$src_fs = nil
$tgt_fs = nil
$continue = false

# ---------

def display_info
  puts "Default parsing path:", '  ' + $product_data_path
  puts "Default local db-data source:", '  ' + $from_local
  puts "Default FTP source:", '  ' + $from_ftp
  puts "Default SFTP source:", '  ' + $from_sftp
  puts "Default local db-data target:", '  ' + $to_local
  puts "Default FTP target:", '  ' + $to_ftp
  puts "Default SFTP target:", '  ' + $to_sftp
  exit
end

def parse_commandline
  $opts.each do |option, argument|
    case option.downcase
      when '--path'; $product_data_path = File.expand_path(argument.to_s).fix_pathname
      when '--from-ftp'
        raise 'Can only have one source' unless $source.nil?
        $source = :ftp
        $from_ftp = argument.to_s.fix_pathname unless argument.to_s.strip.empty?
      when '--from-sftp'
        raise 'Can only have one source' unless $source.nil?
        $source = :sftp
        $from_sftp = argument.to_s.fix_pathname unless argument.to_s.strip.empty?
      when '--from-local'
        raise 'Can only have one source' unless $source.nil?
        $source = :local
        $from_local = File.expand_path(argument.to_s).fix_pathname unless argument.to_s.strip.empty?
      when '--to-ftp'
        raise 'Can only have one target' unless $target.nil?
        $target = :ftp
        $to_ftp = argument.to_s.fix_pathname unless argument.to_s.strip.empty?
      when '--to-sftp'
        raise 'Can only have one target' unless $target.nil?
        $target = :sftp
        $to_sftp = argument.to_s.fix_pathname unless argument.to_s.strip.empty?
      when '--to-local'
        raise 'Can only have one target' unless $target.nil?
        $target = :local
        $to_local = File.expand_path(argument.to_s).fix_pathname unless argument.to_s.strip.empty?
      when '--continue'
        $continue = true
    end
  end

  display_info if $opts.has_key?('--info')

  if $source == :ftp then
    $logger.writeln "Syncing from FTP (#{$from_ftp})"
  elsif $source == :sftp then
    $logger.writeln "Syncing from SFTP (#{$from_sftp})"
  elsif $source == :local then
    $logger.writeln "Syncing from local (#{$from_local})"
  end

  if $target == :ftp then
    $logger.writeln "Syncing to FTP (#{$to_ftp}):"
  elsif $target == :sftp then
    $logger.writeln "Syncing to SFTP (#{$to_sftp}):"
  elsif $target == :local then
    $logger.writeln "Syncing to local (#{$to_local}):"
  end

  if ($source == :ftp || $source == :sftp) && ($target == :ftp || $target == :sftp) then
    $logger.error "Sorry, (S)FTP to (S)FTP syncing not yet supported."
  end

  require 'FTPUploader.rb' if $source == :ftp || $target == :ftp
  require 'SFTPUploader.rb' if $source == :sftp || $target == :sftp

  if $source == :ftp then
    if /^(ftp\:\/\/)?([^\/:]+)(\:(\d+))?(\/.*)?$/i.match($from_ftp) then
      ftp_host = $2
      ftp_port = ($4 || 21).to_i
      ftp_remote_path = $5 || ''
      $logger.error 'Specify $ftp_data_username and $ftp_data_password in the project user settings' if $ftp_data_username == 'REDACTED' || $ftp_data_password == 'REDACTED'
    else
      $logger.error "Not a valid FTP location: #{$from_ftp}"
    end
    $src_fs = FTPUploader.new($logger)
    $src_fs.connect ftp_host, ftp_port, $ftp_data_username, $ftp_data_password, ftp_remote_path
    $source_path = ftp_remote_path

  elsif $source == :sftp then
    if /^(sftp\:\/\/)?([^\/:]+)(\:(\d+))?(\/.*)?$/i.match($from_sftp) then
      sftp_data_host = $2
      sftp_data_port = ($4 || 22).to_i
      sftp_data_remote_path = $5 || ''
      $logger.error 'Specify $sftp_data_readonly_username and $sftp_data_readonly_password in the project user settings' if $sftp_data_readonly_username == 'REDACTED' || $sftp_data_readonly_password == 'REDACTED'
    else
      $logger.error "Not a valid SFTP location: #{$from_sftp}"
    end
    $src_fs = SFTPUploader.new($logger)
    $src_fs.connect sftp_data_host, sftp_data_port, $sftp_data_readonly_username, $sftp_data_readonly_password, sftp_data_remote_path
    $source_path = sftp_data_remote_path

  elsif $source == :local then
    $logger.error "Source path empty or not given." if $from_local.to_s.strip.empty?
    $logger.error "Source path '#{$from_local}' not found." unless (File.exist?($from_local) && File.directory?($from_local))
    $src_fs = nil
    $source_path = $from_local

  else
    $logger.error "No source found! Specify either --from-ftp, --from-sftp or --from-local."
  end

  if $target == :ftp then
    if /^(ftp\:\/\/)?([^\/:]+)(\:(\d+))?(\/.*)?$/i.match($to_ftp) then
      ftp_host = $2
      ftp_port = ($4 || 21).to_i
      ftp_remote_path = $5 || ''
      $logger.error 'Specify $ftp_data_username and $ftp_data_password in the project user settings' if $ftp_data_username == 'REDACTED' || $ftp_data_password == 'REDACTED'
    else
      $logger.error "Not a valid FTP location: #{$to_ftp}"
    end
    $tgt_fs = FTPUploader.new($logger)
    $tgt_fs.connect ftp_host, ftp_port, $ftp_data_username, $ftp_data_password, ftp_remote_path
    $target_path = ftp_remote_path

  elsif $target == :sftp then
    if /^(sftp\:\/\/)?([^\/:]+)(\:(\d+))?(\/.*)?$/i.match($to_sftp) then
      sftp_data_host = $2
      sftp_data_port = ($4 || 22).to_i
      sftp_data_remote_path = $5 || ''
      $logger.error 'Specify $sftp_data_username and $sftp_data_password in the project user settings' if $sftp_data_username == 'REDACTED' || $sftp_data_password == 'REDACTED'
    else
      $logger.error "Not a valid SFTP location: #{$to_sftp}"
    end
    $tgt_fs = SFTPUploader.new($logger)
    $tgt_fs.connect sftp_data_host, sftp_data_port, $sftp_data_username, $sftp_data_password, sftp_data_remote_path
    $target_path = sftp_data_remote_path

  elsif $target == :local then
    $logger.error "Target path empty or not given." if $to_local.to_s.strip.empty?
    $logger.error "Target path '#{$to_local}' not found." unless (File.exist?($to_local) && File.directory?($to_local))
    $tgt_fs = nil
    $target_path = $to_local

  else
    $logger.error "No target found! Specify either --to-ftp, --to-sftp or --to-local."
  end

  $source_path.chomp!('/')
  $target_path.chomp!('/')
end

# ---------

def file_exists(filename, fs)
  if fs.nil? then
    return File.exists?(filename)
  else
    filename_dir = File.dirname(filename)
    filename_file = File.basename(filename)
    fs.chdir(filename_dir) unless fs.getdir == filename_dir
    return fs.file_exists?(filename_file)
  end
end

def make_file_dir(filename, fs)
  filename_dir = File.dirname(filename)
  if fs.nil? then
    FileUtils.mkpath(filename_dir) unless File.exists?(filename_dir) && File.directory?(filename_dir)
  else
    fs.mkpath(filename_dir) unless fs.dir_exists?(filename_dir)
    fs.chdir(filename_dir) unless fs.getdir == filename_dir
  end
end

def file_size(filename, fs)
  if fs.nil? then
    return File.size(filename)
  else
    filename_file = File.basename(filename)
    return fs.file_size(filename_file)
  end
end

def file_time(filename, fs)
  if fs.nil? then
    return File.mtime(filename)
  else
    filename_file = File.basename(filename)
    return fs.file_mtime(filename_file)
  end
end

def compare_file_time(filename_a, fs_a, filename_b, fs_b)
  a = file_time(filename_a, fs_a)
  b = file_time(filename_b, fs_b)
  if fs_a.nil? && fs_b.nil? then
    return a == b
  else
    return a <= b
  end
end

def copy_file(copy_from, fs_from, copy_to, fs_to)
  if fs_from.nil? && fs_to.nil? then
    copy_from.gsub!('/', File::SEPARATOR)
    copy_to.gsub!('/', File::SEPARATOR)
    rv = system("COPY /Y \"#{copy_from}\" \"#{copy_to}\" > NUL")
    $logger.error 'Error during copy' unless rv && ($? == 0)
    puts 'Copied.'
  elsif fs_from.nil? then
    copy_from.gsub!('/', File::SEPARATOR)
    fs_to.upload_text_file(copy_from)
    puts 'Uploaded.'
  elsif fs_to.nil? then
    copy_to.gsub!('/', File::SEPARATOR)
    original_mtime = file_time(copy_from, fs_from)
    fs_from.download_text_file(copy_from, copy_to)
    File.utime(File.atime(copy_to), original_mtime, copy_to) # Local file should have same mtime!
    puts 'Downloaded.'
  else
    $logger.error 'Operation not yet supported'
  end
end

# ---------

def sync
  $datasources.each { |datasource|
    [false, true].each{ |is_infofile|

      datasource = datasource.chomp(File.extname(datasource)) + '.info' if is_infofile

      copy_from = datasource.gsub('{data_folder}', $source_path)
      if file_exists(copy_from, $src_fs) then
        print '  ' + copy_from + ' ... '

        copy_to = datasource.gsub('{data_folder}', $target_path)
        make_file_dir(copy_to, $tgt_fs)

        skip = false
        if file_exists(copy_to, $tgt_fs) then
          if file_size(copy_from, $src_fs) == file_size(copy_to, $tgt_fs) then
            if compare_file_time(copy_from, $src_fs, copy_to, $tgt_fs) then
              skip = true
            end
          end
        end

        if skip then
          puts 'OK.'
        else
          copy_file(copy_from, $src_fs, copy_to, $tgt_fs)
        end
      else
        if $continue then
          $logger.writeln "File not found: #{copy_from}" unless is_infofile
        else
          $logger.error "File not found: #{copy_from}" unless is_infofile
        end
      end
    }
  }
end

# ---------

parse_commandline

$datasources = DataSourceCollector.collect($logger, $product_data_path, $common_data_path, nil).keys

sync
