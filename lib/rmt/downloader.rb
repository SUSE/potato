module RMT
end

require 'typhoeus'
require 'tempfile'
require 'fileutils'
require 'fiber'

class RMT::Downloader

  class Exception < RuntimeError
  end

  KNOWN_HASH_FUNCTIONS = %i(MD5 SHA1 SHA256 SHA384 SHA512).freeze

  attr_accessor :repository_url, :local_path, :concurrency, :logger

  def initialize(repository_url, local_path, logger = nil)
    Typhoeus::Config.user_agent = "RMT/#{RMT::VERSION}"
    @repository_url = repository_url
    @local_path = local_path
    @concurrency = 4
    @logger = logger || Logger.new('/dev/null')
  end

  def verify_checksum(filename, checksum_type, checksum_value)
    hash_function = checksum_type.gsub(/\W/, '').upcase.to_sym
    unless (KNOWN_HASH_FUNCTIONS.include? hash_function)
      raise Exception.new("Unknown hash function #{checksum_type}")
    end

    digest = Digest.const_get(hash_function).file(filename)

    raise Exception.new('Checksum doesn\'t match') unless (checksum_value == digest.to_s)
  end

  def download(remote_file, checksum_type = nil, checksum_value = nil)
    local_file = make_local_path(remote_file)

    request_fiber = Fiber.new do
      make_request(remote_file, local_file, request_fiber, checksum_type, checksum_value)
    end

    request_fiber.resume.run

    local_file
  end

  def download_multi(files)
    @queue = files
    @hydra = Typhoeus::Hydra.new(max_concurrency: @concurrency)

    iterator_fiber = Fiber.new do
      @queue.each do |queue_item|
        request_fiber = Fiber.new do
          begin
            remote_file = queue_item.location
            local_file = make_local_path(remote_file)
            make_request(remote_file, local_file, request_fiber, queue_item[:checksum_type], queue_item[:checksum])
          rescue RMT::Downloader::Exception => e
            @logger.info("E #{File.basename(local_file)} - #{e}")
          ensure
            iterator_fiber.resume if iterator_fiber.alive?
          end
        end

        @hydra.queue(request_fiber.resume)
        Fiber.yield
      end
      Fiber.yield
    end

    @concurrency.times { iterator_fiber.resume }

    @hydra.run
  end

  protected

  def make_request(remote_file, local_file, request_fiber, checksum_type = nil, checksum_value = nil)
    uri = URI.join(@repository_url, remote_file)
    downloaded_file = Tempfile.new('rmt')

    request = Typhoeus::Request.new(uri.to_s, followlocation: true)
    request.on_headers {|response| request_fiber.resume(response) }
    request.on_body do |chunk|
      next :abort if downloaded_file.closed?
      downloaded_file.write(chunk)
    end
    request.on_complete do |response|
      request_fiber.resume(response) if request_fiber.alive?
    end

    response = Fiber.yield(request)

    begin
      if (URI(uri).scheme != 'file' and response.code != 200)
        raise RMT::Downloader::Exception.new("#{remote_file} - HTTP request failed with code #{response.code}")
      end

      response = Fiber.yield
      if (response.return_code and response.return_code != :ok)
        raise RMT::Downloader::Exception.new("#{remote_file} - return code #{response.return_code}")
      end

      downloaded_file.close

      verify_checksum(downloaded_file.path, checksum_type, checksum_value) if (checksum_type and checksum_value)
    rescue StandardError => e
      downloaded_file.unlink
      raise e
    end

    FileUtils.mv(downloaded_file.path, local_file)

    @logger.info("D #{File.basename(local_file)}")
  end

  def make_local_path(remote_file)
    filename = File.join(@local_path, remote_file)
    dirname = File.dirname(filename)

    FileUtils.mkdir_p(dirname)

    filename
  end

end
