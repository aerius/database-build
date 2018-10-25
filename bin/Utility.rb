ON_WINDOWS = (RUBY_PLATFORM =~ /mswin|mingw|cygwin/)


##
# Extend classes
#
class String

  # Does the string end with the specified +suffix+?
  def ends_with?(suffix)
    suffix = suffix.to_s
    return (self[-suffix.length, suffix.length] == suffix)
  end
  def starts_with?(prefix)
    prefix = prefix.to_s
    return (self[0, prefix.length] == prefix)
  end

  # Fix slashes in paths and such
  def fix_pathname
    pathname = self.gsub('\\', '/')
    pathname += '/' unless pathname.ends_with?('/')
    return pathname
  end
  def fix_filename
    return self.gsub('\\', '/')
  end
end

##
# Our own utility class
#
class Utility

  NUM_ASTERISKS = 50

  def self.run_cmd(command, log_output = true, additional_info = '', logger = $logger)
    if log_output && !logger.nil? && !logger.commandlog_filename.nil? then
      File.open(logger.commandlog_filename, 'a') { |f| f.puts '', '', '*' * NUM_ASTERISKS, "[#{Time.now.strftime('%d-%m-%Y %H:%M:%S')}] #{additional_info}", command, '*' * NUM_ASTERISKS }
      command += ' >> "' + logger.commandlog_filename + '" 2>&1'
    end
    return system(command) && ( $? == 0 )
  end

  def self.fetch_cmd(command, log_output = true, additional_info = '', logger = $logger)
    do_log = log_output && !logger.nil? && !logger.commandlog_filename.nil?
    File.open(logger.commandlog_filename, 'a') { |f| f.puts '', '', '*' * NUM_ASTERISKS, "[#{Time.now.strftime('%d-%m-%Y %H:%M:%S')}] #{additional_info}", command, '*' * NUM_ASTERISKS, 'Output:' } if do_log
    command += ' 2>&1' # redirect STDERR to STDOUT
    socket = IO.popen(command)
    rv = socket.gets(nil)
    socket.close
    File.open(logger.commandlog_filename, 'a') { |f| f.puts rv, "Exit code: #{$?.to_i}" } if do_log
    rv = nil if $? != 0
    return rv
  end

  def self.get_last_cmd_output(lines)
    lastnum = 0
    lines.reverse.each{ |line|
      break if line.strip == '*' * NUM_ASTERISKS
      lastnum += 1
    }
    return lines.last(lastnum).join("")
  end

  def self.get_git_hash
    raise 'Git bin path not set ($git_bin_path)' if $git_bin_path.nil?
    raise "Git bin path not found ($git_bin_path = \"#{$git_bin_path}\")" unless ((File.exist?($git_bin_path) && File.directory?($git_bin_path)) || ($git_bin_path.empty?))

    curr_dir = Dir.pwd
    Dir.chdir($product_sql_path)
    cmd = "\"#{$git_bin_path}git\" log -1 --pretty=format:%h"
    socket = IO.popen(cmd)
    begin
      if line = socket.gets then
        line = line.strip
        raise "Illegal git hash found: #{line}" if line.length > 10
        return line
      end
    ensure
      socket.close
      Dir.chdir(curr_dir)
    end
    raise "Could not read GIT hash with command: #{cmd}"
  end

  def self.get_svn_head_revision
    raise 'SVN bin path not set ($svn_bin_path)' if $svn_bin_path.nil?
    raise "SVN bin path not found ($svn_bin_path = \"#{$svn_bin_path}\")" unless ((File.exist?($svn_bin_path) && File.directory?($svn_bin_path)) || ($svn_bin_path.empty?))
    raise "Cannot determine svn HEAD revision: svn root URL not set ($svn_root_url)" if $svn_root_url.nil?

    cmd = "\"#{$svn_bin_path}svn\" info \"#{$svn_root_url}\""
    socket = IO.popen(cmd)
    begin
      while line = socket.gets
        if line.index("evision")
          revision = line.split()[1].strip()
          return revision.to_i.to_s
        end
      end
    ensure
      socket.close
    end
    raise "Could not read SVN revision number with command: #{cmd}"
  end

  def self.format_duration(seconds)
    str = ''
    if seconds >= (24*60*60) then
      days = (seconds/(24*60*60)).to_i
      str += " #{days}d"
      seconds -= days*(24*60*60)
    end
    if seconds >= (60*60) then
      hours = (seconds/(60*60)).to_i
      str += " #{hours}h"
      seconds -= hours*(60*60)
    end
    if seconds >= 60 then
      minutes = (seconds/60).to_i
      str += " #{minutes}m"
      seconds -= minutes*60
    end
    if seconds.to_i > 0 || str.empty? then
      str += " #{seconds.round}s"
    end
    return str.strip
  end

  def self.format_filesize(bytes)
    pretty_map = {
      'B'  => 1024,
      'KB' => 1024 * 1024,
      'MB' => 1024 * 1024 * 1024,
      'GB' => 1024 * 1024 * 1024 * 1024,
      'TB' => 1024 * 1024 * 1024 * 1024 * 1024
    }

    pretty_map.each_pair { |pretty_name, pretty_size|
      if bytes < pretty_size
        pretty_bytes = (bytes.to_f / (pretty_size / 1024)).round(1)
        return "#{pretty_bytes} #{pretty_name}"
      end
    }
    return bytes.to_s
  end

  def self.find_best_postgresql_path(parent_path)
    parent_path = parent_path.fix_pathname
    ['9.5', '9.4', '9.3', '9.2'].each{ |version|
      pg_path = parent_path + 'PostgreSQL/' + version + '/bin/'
      return pg_path if File.exists?(pg_path) && File.directory?(pg_path)
    }
    return parent_path + 'PostgreSQL/9.5/bin/'
  end

  def self.is_ruby_version_below(version_str)
    return ((RUBY_VERSION.split('.').map{ |v| v.to_i }) <=> (version_str.split('.').map{ |v| v.to_i })) < 0
  end

end
