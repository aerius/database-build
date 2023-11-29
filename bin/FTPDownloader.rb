require 'net/ftp'

##
# Utility class for several FTP actions. Similar to HTTPSDownloader and SFTPDownloader so easily interchangeable.
#
class FTPDownloader

  def initialize(logger)
    @logger = logger
    @ftp = Net::FTP.new
  end

  def connect(host, port, username, password, remote_path)
    @logger.log "FTP connect: #{host}:#{port}, username: #{username}, remote folder: #{remote_path}"
    #@ftp.debug_mode = true
    @ftp.passive = true
    @ftp.connect(host, port)
    @ftp.login(username, password)
    @ftp.chdir(remote_path)
  end

  def download_binary_file(filename, download_to_path)
    @logger.log "FTP binary download: #{filename}"
    @ftp.getbinaryfile(File.basename(filename), download_to_path)
  end

  def download_text_file(filename, download_to_path)
    @logger.log "FTP text download: #{filename}"
    @ftp.gettextfile(File.basename(filename), download_to_path)
  end

  def disconnect
    @logger.log "FTP disconnect"
    @ftp.close
  end

  def getdir
    return @ftp.pwd
  end

  def chdir(remote_path)
    @ftp.chdir(remote_path)
  end

  def file_exists?(remote_path)
    currpath = @ftp.pwd
    begin
      remote_dir = File.dirname(remote_path)
      @ftp.chdir(remote_dir) if remote_dir != currpath && !remote_dir.empty?
      begin
        dummy = @ftp.size(File.basename(remote_path))
        return true
      rescue Net::FTPReplyError
        return false
      end
    rescue Net::FTPPermError
      return false
    ensure
      @ftp.chdir(currpath)
    end
  end

  def file_size(remote_path)
    return @ftp.size(remote_path)
  end

  def file_mtime(remote_path)
    return @ftp.mtime(remote_path)
  end

end
