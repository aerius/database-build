require 'rubygems'
begin
  require 'net/ssh'
  require 'net/sftp'
rescue LoadError => e
  puts e.message
  puts 'Please run the following command to install this Ruby library:'
  if e.message.include?('net/ssh')
    puts '  gem install net-ssh'
  else
    puts '  gem install net-sftp'
  end
  exit
end

##
# Utility class for several SFTP actions. Similar to HTTPSDownloader and FTPDownloader so easily interchangeable.
#
class SFTPDownloader

  def initialize(logger)
    @logger = logger
    @sftp = nil
    @currdir = ''
  end

  def connect(host, port, username, password, remote_path)
    @logger.log "SFTP connect: #{host}:#{port}, username: #{username}, remote folder: #{remote_path}"
    begin
      @sftp = Net::SFTP.start(host, username, { :port => port, :password => password, :compression => false, :encryption => '3des-cbc' })
    rescue Net::SSH::Exception => e
      if e.message.include?('Creation of file mapping failed with error: 998') then
        raise e, "#{e} -- Possible fix: Try closing Pageant.exe", e.backtrace
      else
        raise
      end
    end
    chdir(remote_path)
  end

  def download_file(filename, download_to_path)
    @logger.log "SFTP download: #{filename}"
    @sftp.download!(filename, download_to_path)
  end
  def download_binary_file(filename, download_to_path); download_file(filename, download_to_path); end
  def download_text_file(filename, download_to_path); download_file(filename, download_to_path); end

  def disconnect
    @logger.log "SFTP disconnect"
    @sftp.session.close
    @sftp = nil
  end

  def getdir
    return @currdir
  end

  def chdir(remote_path)
    remote_path = @sftp.realpath!(remote_path.fix_pathname).name
    @currdir = remote_path.fix_pathname
  end

  def file_exists?(remote_file)
    #remote_path = @sftp.realpath!((@currdir + remote_file).fix_filename).name
    remote_path = (@currdir + remote_file).fix_filename
    begin
      handle = @sftp.open!(remote_path)
      @sftp.close!(handle)
      return true
    rescue Net::SFTP::StatusException
      return false
    end
  end

  def file_size(remote_file)
    remote_path = @sftp.realpath!((@currdir + remote_file).fix_filename).name
    attributes = @sftp.stat!(remote_path)
    return attributes.size
  end

  def file_mtime(remote_file)
    remote_path = @sftp.realpath!((@currdir + remote_file).fix_filename).name
    attributes = @sftp.stat!(remote_path)
    return Time.at(attributes.mtime)
  end

  def get_filenames(remote_path, pattern = '*')
    files = []
    @sftp.dir.glob(remote_path, pattern) do |entry|
      files << entry.name
    end
    return files
  end

end
