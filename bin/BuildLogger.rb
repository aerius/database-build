##
# Utility class for keeping a log of the performed actions.
#
class BuildLogger

  attr_accessor :log_filename, :commandlog_filename, :hint_level

  def initialize
    @hint_level = HINT_LEVEL_ALL
  end

  def open(log_path, prefix = '', suffix = '')
    FileUtils.mkdir_p(log_path) unless File.exists?(log_path)
    prefix = prefix + '_' unless prefix.empty?
    suffix = '_' + suffix unless suffix.empty?
    @log_filename = log_path + "#{prefix}output#{suffix}.log"
    @commandlog_filename = log_path + "#{prefix}commands#{suffix}.log"
    @log_file = File.open(@log_filename, 'a')
    @log_file.puts '', '', '', '=' * 100, "Log opened @ #{Time.now.strftime('%d-%m-%Y %H:%M:%S')}", '=' * 100
    writeln "Logging file: #{@log_filename}"
  end

  def close
    unless @log_file.nil? then
      @log_file.puts '=' * 100
      @log_file.close
      @log_file = nil
    end
  end

  # Log to file only.
  def log(str)
    @log_file.puts "[#{Time.now.strftime('%d-%m-%Y %H:%M:%S')}] #{str}" unless @log_file.nil?
  end

  # Write to screen and log to file, no newline on screen.
  def write(str)
    log(str)
    print str
  end

  # Write to screen and log to file, with newline.
  def writeln(str)
    log(str)
    puts str
  end

  # Write to screen and log to file; takes a block for which the run duration will be measured, writes this time to the
  # screen (on the same line) when done. The logfile already contains timestamps so nothing different is done there.
  # In case of an error, no timing is printed, only a newline.
  def writeln_with_timing(str, max_strlength = -1)
    log(str)
    print cut_string_start(str, max_strlength)
    begin
      starttime = Time.now
      yield
      puts " (#{Utility.format_duration(Time.now - starttime)})"
    rescue
      puts '' #newline
      raise
    end
  end

  # Raise error and log to file.
  def error(str, max_strlength = -1)
    log('FATAL ERROR: ' + str)
    raise cut_string_start(str, max_strlength)
  end

  def error_sql(str, original_filename = '', max_strlength = -1)
    log('FATAL SQL ERROR' + (original_filename.empty? ? '' : ' @ ' + original_filename) + ":\n" + str)
    puts '', "\u25BA\u25BA An error occured executing " + (original_filename.empty? ? 'SQL' : original_filename) + ':', '', cut_string_end(str, max_strlength)
    raise 'SQL error'
  end

  def warn(str)
    writeln('WARNING: ' + str)
  end

  def hint_level=(level)
    if [HINT_LEVEL_OFF, HINT_LEVEL_MAJOR, HINT_LEVEL_ALL].include?(level.to_i) then
      @hint_level = level.to_i
    else
      raise 'Expected hint level 0, 1 or 2.'
    end
  end

  def major_hint(str)
      log('HINT: ' + str)
    puts 'HINT: ' + str if @hint_level >= HINT_LEVEL_MAJOR
  end

  def minor_hint(str)
      log('HINT: ' + str)
    puts 'HINT: ' + str if @hint_level >= HINT_LEVEL_ALL
  end

  def clear
    if !@log_file.nil? then
      @log_file.close
      @log_file = File.open(@log_filename, 'w')
    elsif !@log_filename.nil? && File.exist?(@log_filename) then
      File.open(@log_filename).close
    end

    File.open(@commandlog_filename, 'w').close if !@commandlog_filename.nil? && File.exist?(@commandlog_filename)

    # Delete possible thread logs
    unless @commandlog_filename.nil? then
      Dir[File.dirname(@log_filename) + "/" + File.basename(@log_filename, File.extname(@log_filename)) + "_*"].each{ |filename|
        File.delete(filename)
      }
    end
    unless @commandlog_filename.nil? then
      Dir[File.dirname(@commandlog_filename) + "/" + File.basename(@commandlog_filename, File.extname(@commandlog_filename)) + "_*"].each{ |filename|
        File.delete(filename)
      }
    end
  end

 private

  def cut_string_start(str, max_strlength)
    return (max_strlength != -1 && str.length > max_strlength) ? (str[0, max_strlength] + '...') : str
  end

  def cut_string_end(str, max_strlength)
    return (max_strlength != -1 && str.length > max_strlength) ? ('...' + str[str.length - max_strlength, str.length]) : str
  end

end
