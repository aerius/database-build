require 'net/http'
require 'openssl'
require 'uri'
require 'time'

##
# Utility class for several HTTPS actions. Similar to FTPUploader and SFTPUploader so easily interchangeable.
#
class HTTPSUploader

  def initialize(logger)
    @logger = logger
    @base_url = nil
    @currdir = ''
  end

  def connect(base_url, username, password)
    @logger.log "HTTPS connect: #{base_url}, username: #{username}"
    @base_url = base_url
    @username = username
    @password = password
  end

  def upload_file(filename)
    raise "Upload file not supported with HTTPS version"
  end
  def upload_binary_file(filename); upload_file(filename); end
  def upload_text_file(filename); upload_file(filename); end

  def download_file(filename, download_to_path)
    @logger.log "HTTPS download: #{filename}"
    
    uri = URI(@base_url + filename)

    Net::HTTP.start(uri.host, uri.port, :use_ssl => true) do |http|
      req = Net::HTTP::Get.new(uri.request_uri)
      set_auth(req)
      resp = http.request(req)
      open(download_to_path, "wb") do |file|
          file.write(resp.body)
      end
    end
  end
  def download_binary_file(filename, download_to_path); download_file(filename, download_to_path); end
  def download_text_file(filename, download_to_path); download_file(filename, download_to_path); end

  def disconnect
    @logger.log "HTTPS disconnect"
  end

  def getdir
    return @currdir
  end

  def chdir(remote_path)
    @currdir = remote_path.fix_pathname
  end

  def mkpath(remote_path)
    raise "Creating remote path not supported with HTTPS version"
  end

  def dir_exists?(remote_path)
    # No way to check this (afaik), but probably not needed as it's only needed in upload.
  end

  def file_exists?(remote_file)
    uri = URI(@base_url + @currdir + remote_file)
    Net::HTTP.start(uri.host, uri.port, :use_ssl => true) do |http|
      req = Net::HTTP::Head.new(uri.request_uri)
      set_auth(req)
      resp = http.request(req)
      status_code = resp.code.to_i
      @logger.error "Unexpected http status code: #{status_code}" unless status_code == 200 || status_code == 404
      return status_code == 200
    end
  end

  def file_size(remote_file)
    uri = URI(@base_url + @currdir + remote_file)
    Net::HTTP.start(uri.host, uri.port, :use_ssl => true) do |http|
      req = Net::HTTP::Head.new(uri.request_uri)
      set_auth(req)
      resp = http.request(req)
      return resp.content_length
    end
  end

  def file_mtime(remote_file)
    uri = URI(@base_url + @currdir + remote_file)
    Net::HTTP.start(uri.host, uri.port, :use_ssl => true) do |http|
      req = Net::HTTP::Head.new(uri.request_uri)
      set_auth(req)
      resp = http.request(req)
      return Time.parse(resp.get_fields('last-modified')[0])
    end
  end

  def get_filenames(remote_path, pattern = '*')
    files = []
		# Unsure if this possible and/or required.
    return files
  end

  private

  def set_auth(req)
    req.basic_auth @username, @password unless $https_data_username.nil? || $https_data_password.nil?
  end

end
