require 'net/http'
require 'openssl'
require 'uri'
require 'time'

##
# Utility class for several HTTPS actions. Similar to FTPDownloader and SFTPDownloader so easily interchangeable.
#
class HTTPSDownloader

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

  def download_file(filename, download_to_path)
    @logger.log "HTTPS download: #{filename}"
    
    uri = URI(@base_url + filename)

    Net::HTTP.start(uri.host, uri.port, :use_ssl => true) do |http|
      req = Net::HTTP::Get.new(uri.request_uri)
      set_auth(req)
      http.request(req) do |resp|
        open(download_to_path, "wb") do |file|
          resp.read_body do |body|
            file.write(body)
          end
        end
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

  private

  def set_auth(req)
    req.basic_auth @username, @password unless $https_data_username.nil? || $https_data_password.nil?
  end

end
