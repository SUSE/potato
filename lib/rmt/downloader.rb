require 'typhoeus'
require 'tempfile'
require 'fileutils'
require 'fiber'
require 'rmt'
require 'rmt/config'
require 'rmt/fiber_request'
require 'rmt/deduplicator'

class RMT::Downloader
  class Exception < RuntimeError
    attr_reader :http_code

    def initialize(message, http_code = nil)
      @http_code = http_code
      super(message)
    end
  end

  attr_accessor :concurrency, :logger, :auth_token

  def initialize(logger:, auth_token: nil, track_files: true)
    Typhoeus::Config.user_agent = "RMT/#{RMT::VERSION}"
    @concurrency = 4
    @auth_token = auth_token
    @logger = logger
    @track_files = track_files
    @queue = []
  end

  def download(file_reference)
    downloads_needed, _ = try_copying_from_cache([file_reference])
    return file_reference.local_path if downloads_needed.empty?

    fiber_request = create_fiber_request(file_reference)
    fiber_request.run
    file_reference.local_path
  end

  def download_multi(files, ignore_errors: false)
    downloads_needed, failed_cache =
      try_copying_from_cache(files, ignore_errors: ignore_errors)
    return failed_cache if downloads_needed.empty?

    @queue = downloads_needed
    @hydra = Typhoeus::Hydra.new(max_concurrency: @concurrency)

    failed_downloads = ignore_errors ? failed_cache : nil
    @concurrency.times { process_queue(failed_downloads) }

    @hydra.run
    failed_downloads
  end

  protected

  # Creates a fiber that wraps RMT::FiberRequest and runs it, returning the RMT::FiberRequest object.
  # @param [RMT::Mirror::FileReference] file_reference with all file metadata attributes and paths (remote, local, cache)
  # @param [Array] failed_downloads array of remote files that have failed downloads, passed by reference, prevents from raising RMT::Downloader exceptions
  # @return [RMT::FiberRequest] a request that can be run individually or with Typhoeus::Hydra
  def create_fiber_request(file_reference, failed_downloads: nil)
    make_file_dir(file_reference.local_path)

    request_fiber = Fiber.new do
      begin
        # make_request will call Fiber.yield on this fiber (request_fiber), returning the request object
        # this fiber will be resumed by on_body callback once the request is executed
        response = make_request(file_reference, request_fiber)
        finalize_download(response.request, file_reference)
      rescue RMT::Downloader::Exception, RMT::ChecksumVerifier::Exception => e
        unless failed_downloads
          # Clean up downloads queued in Ethon::Multi and @queue
          if @hydra
            @queue = []
            @hydra.multi.easy_handles.each do |handle|
              @hydra.multi.delete(handle)
            end
          end

          raise(e)
        end

        @logger.warn("× #{File.basename(file_reference.local_path)} - #{e}")
        failed_downloads << file_reference.local_path
      ensure
        process_queue(failed_downloads)
      end
    end

    request_fiber.resume
  end

  def process_queue(failed_downloads = nil)
    queue_item = @queue.shift
    return unless queue_item

    request = create_fiber_request(queue_item, failed_downloads: failed_downloads)
    @hydra.queue(request)
  end

  def make_request(file, request_fiber)
    downloaded_file = Tempfile.new('rmt', Dir.tmpdir, mode: File::BINARY, encoding: 'ascii-8bit')

    request = RMT::FiberRequest.new(
      request_uri(file).to_s,
      download_path: downloaded_file,
      request_fiber: request_fiber,
      followlocation: true
    )

    request.receive_headers
    request.receive_body
  end

  def try_copying_from_cache(files, ignore_errors: false)
    # We need to verify if the cached copy is still relevant
    # Create a HTTP/HTTPS HEAD request if possible, return nil if not
    cache_requests = files.map { |file| [file, cache_head_request(file)] }.to_h
    available_in_cache = cache_requests.compact.values

    # Download everything if the cache is empty
    return [files, []] if available_in_cache.empty?

    Typhoeus::Hydra.new(max_concurrency: @concurrency)
      .tap { |hydra| available_in_cache.each { |request| hydra.queue(request) } }.run

    downloads_needed = []
    failed_files = []
    cache_requests.each do |file, request|
      next downloads_needed << file if request.nil?
      next downloads_needed << file unless valid_cached_file?(file, request.response)

      copy_from_cache(file)
    rescue RMT::Downloader::Exception => e
      next failed_files << file.local_path if ignore_errors

      raise e
    end

    [downloads_needed, failed_files]
  end

  def cache_head_request(file)
    # RMT must not make HEAD requests when importing repos (file://)
    return nil unless %w[http https].include?(file.remote_path.scheme)
    return nil if file.cache_timestamp.nil?

    RMT::HttpRequest.new(request_uri(file).to_s, method: :head, followlocation: true)
  end

  def valid_cached_file?(file, response)
    raise http_error(file.remote_path, response.code) if (response.code != 200)

    # response.headers returns Typhoeus::Response::Headers, which takes care of
    # case-sensitive concerns with the header's key
    last_modified_header = response.headers['Last-Modified']
    return false unless last_modified_header

    file.cache_timestamp == Time.parse(last_modified_header).utc
  end

  def copy_from_cache(file)
    make_file_dir(file.local_path)
    FileUtils.cp(file.cache_path, file.local_path, preserve: true) unless (file.cache_path == file.local_path)
    @logger.info("→ #{File.basename(file.local_path)}")
    @logger.debug("(cached mtime matches server last modified: #{file.cache_timestamp})")
  end

  def finalize_download(request, file)
    if (URI(request.base_url).scheme != 'file') && request.response.code != 200
      raise http_error(request.remote_file, request.response.code)
    end

    handle_checksum_verification!(file.checksum_type, file.checksum, request.download_path)

    FileUtils.mv(request.download_path.path, file.local_path)
    File.chmod(0o644, file.local_path)

    last_modified = request.response.headers['Last-Modified']
    if last_modified
      timestamp = Time.parse(last_modified).utc
      File.utime(timestamp, timestamp, file.local_path)
    end

    if @track_files && file.local_path.match?(/\.(rpm|drpm)$/)
      DownloadedFile.track_file(checksum: file.checksum,
                                checksum_type: file.checksum_type,
                                local_path: file.local_path,
                                size: File.size(file.local_path))
    end

    @logger.info("↓ #{File.basename(file.local_path)}")
    @logger.debug("(new mtime: #{File.mtime(file.local_path).utc})")
  rescue StandardError => e
    request.download_path.unlink
    raise e
  end

  def handle_checksum_verification!(checksum_type, checksum_value, download_path)
    return unless (checksum_type && checksum_value)

    unless RMT::ChecksumVerifier.match_checksum?(checksum_type, checksum_value, download_path)
      raise RMT::Downloader::Exception.new(_("Checksum doesn't match"))
    end
  end

  def http_error(remote_file, http_code)
    RMT::Downloader::Exception.new(
      _('%{file} - HTTP request failed with code %{code}') % { file: remote_file, code: http_code },
      http_code
    )
  end

  def request_uri(file)
    uri = URI.join(file.remote_path)
    uri.query = @auth_token if (@auth_token && uri.scheme != 'file')

    if URI(uri).scheme == 'file' && !File.exist?(uri.path)
      raise RMT::Downloader::Exception.new(_('%{file} - File does not exist') % { file: file.remote_path })
    end

    uri.to_s
  end

  def make_file_dir(file_path)
    dirname = File.dirname(file_path)

    FileUtils.mkdir_p(dirname)
  end
end
