require 'rmt/downloader'
require 'rmt/gpg'
require 'repomd_parser'
require 'time'

class RMT::Mirror
  class RMT::Mirror::Exception < RuntimeError
  end

  include RMT::Deduplicator
  include RMT::FileValidator

  def initialize(mirroring_base_dir: RMT::DEFAULT_MIRROR_DIR, logger:, mirror_src: false, airgap_mode: false)
    @mirroring_base_dir = mirroring_base_dir
    @logger = logger
    @mirror_src = mirror_src
    @airgap_mode = airgap_mode
    @deep_verify = false

    # don't save files for deduplication when in offline mode
    @downloader = RMT::Downloader.new(logger: logger, track_files: !airgap_mode)
  end

  def mirror_suma_product_tree(repository_url:)
    # we have an inconsistency in how we mirror in offline mode
    # in normal mode we mirror in the following way:
    # base_dir/repo/...
    # however, in offline mode we mirror in the following way
    # base_dir/...
    # we need this extra step to ensure that we write to the public directory
    base_dir = mirroring_base_dir
    base_dir = File.expand_path(File.join(mirroring_base_dir, '/../')) if mirroring_base_dir == RMT::DEFAULT_MIRROR_DIR

    repository_dir = File.join(base_dir, '/suma/')
    mirroring_paths = {
      base_url: URI.join(repository_url),
      base_dir: repository_dir,
      cache_dir: repository_dir
    }

    logger.info _('Mirroring SUSE Manager product tree to %{dir}') % { dir: repository_dir }
    downloader.download(FileReference.new(relative_path: 'product_tree.json', **mirroring_paths))
  rescue RMT::Downloader::Exception => e
    raise RMT::Mirror::Exception.new(_('Could not mirror SUSE Manager product tree with error: %{error}') % { error: e.message })
  end

  def mirror(repository_url:, local_path:, auth_token: nil, repo_name: nil, do_not_raise: false)
    repository_dir = File.join(mirroring_base_dir, local_path)

    logger.info _('Mirroring repository %{repo} to %{dir}') % { repo: repo_name || repository_url, dir: repository_dir }

    create_repository_dir(repository_dir)
    temp_licenses_dir = create_temp_dir
    # downloading license doesn't require an auth token
    mirror_license(repository_dir, repository_url, temp_licenses_dir)

    downloader.auth_token = auth_token
    temp_metadata_dir = create_temp_dir
    metadata_files = mirror_metadata(repository_dir, repository_url, temp_metadata_dir, do_not_raise)
    mirror_packages(metadata_files, repository_dir, repository_url)

    replace_directory(temp_licenses_dir, repository_dir.chomp('/') + '.license/') if Dir.exist?(temp_licenses_dir)
    replace_directory(File.join(temp_metadata_dir, 'repodata'), File.join(repository_dir, 'repodata'))
  ensure
    [temp_licenses_dir, temp_metadata_dir].each { |dir| FileUtils.remove_entry(dir, true) }
  end

  protected

  attr_reader :airgap_mode, :deep_verify, :downloader, :logger, :mirroring_base_dir, :mirror_src

  def create_repository_dir(repository_dir)
    FileUtils.mkpath(repository_dir) unless Dir.exist?(repository_dir)
  rescue StandardError => e
    raise RMT::Mirror::Exception.new(
      _('Could not create local directory %{dir} with error: %{error}') % { dir: repository_dir, error: e.message }
    )
  end

  def create_temp_dir
    Dir.mktmpdir
  rescue StandardError => e
    raise RMT::Mirror::Exception.new(_('Could not create a temporary directory: %{error}') % { error: e.message })
  end

  def mirror_metadata(repository_dir, repository_url, temp_metadata_dir, do_not_raise)
    mirroring_paths = {
      base_url: URI.join(repository_url),
      base_dir: temp_metadata_dir,
      cache_dir: repository_dir
    }

    repomd_xml = FileReference.new(relative_path: 'repodata/repomd.xml', **mirroring_paths)
    downloader.download(repomd_xml)

    begin
      signature_file = FileReference.new(relative_path: 'repodata/repomd.xml.asc', **mirroring_paths)
      key_file       = FileReference.new(relative_path: 'repodata/repomd.xml.key', **mirroring_paths)
      downloader.download(signature_file)
      downloader.download(key_file)

      RMT::GPG.new(
        metadata_file: repomd_xml.local_path,
        key_file: key_file.local_path,
        signature_file: signature_file.local_path,
        logger: logger
      ).verify_signature
    rescue RMT::Downloader::Exception => e
      if (e.http_code == 404)
        logger.info(_('Repository metadata signatures are missing'))
      else
        raise(_('Failed to get repository metadata signatures with HTTP code %{http_code}') % { http_code: e.http_code })
      end
    rescue RMT::GPG::Exception => e
      logger.error "Error while mirroring metadata: #{e.message}"
      unless do_not_raise && e.message.include?('GPG signature verification failed')
        raise RMT::Mirror::Exception.new(_(e.message))
      end
    end

    metadata_files = RepomdParser::RepomdXmlParser.new(repomd_xml.local_path).parse
      .map { |reference| FileReference.build_from_metadata(reference, **mirroring_paths) }

    downloader.download_multi(metadata_files.dup)

    metadata_files
  rescue StandardError => e
    raise RMT::Mirror::Exception.new(_('Error while mirroring metadata: %{error}') % { error: e.message })
  end

  def mirror_license(repository_dir, repository_url, temp_licenses_dir)
    mirroring_paths = {
      base_url: repository_url.chomp('/') + '.license/',
      base_dir: temp_licenses_dir,
      cache_dir: repository_dir.chomp('/') + '.license/'
    }

    begin
      directory_yast = FileReference.new(relative_path: 'directory.yast', **mirroring_paths)
      downloader.download(directory_yast)
    rescue RMT::Downloader::Exception
      FileUtils.remove_entry(temp_licenses_dir) # the repository would have an empty licenses directory unless removed
      return
    end

    license_files = File.readlines(directory_yast.local_path)
      .map(&:strip).reject { |item| item == 'directory.yast' }
      .map { |relative_path| FileReference.new(relative_path: relative_path, **mirroring_paths) }
    downloader.download_multi(license_files)
  rescue StandardError => e
    raise RMT::Mirror::Exception.new(_('Error while mirroring license: %{error}') % { error: e.message })
  end

  def mirror_packages(metadata_files, repository_dir, repository_url)
    package_references = parse_packages_metadata(metadata_files)

    package_file_references = package_references.map do |reference|
      FileReference.build_from_metadata(reference,
                                        base_dir: repository_dir,
                                        base_url: repository_url)
    end

    failed_downloads = download_package_files(package_file_references)

    raise _('Failed to download %{failed_count} files') % { failed_count: failed_downloads.size } unless failed_downloads.empty?
  rescue StandardError => e
    raise RMT::Mirror::Exception.new(_('Error while mirroring data: %{error}') % { error: e.message })
  end

  def parse_packages_metadata(metadata_references)
    xml_parsers = { deltainfo: RepomdParser::DeltainfoXmlParser,
                    primary: RepomdParser::PrimaryXmlParser }

    metadata_references
      .map { |file| xml_parsers[file.type]&.new(file.local_path) }.compact
      .map(&:parse).flatten
  end

  def download_package_files(file_references)
    files_to_download = file_references.select { |file| need_to_download?(file) }
    return [] if files_to_download.empty?

    downloader.download_multi(files_to_download, ignore_errors: true)
  end

  def need_to_download?(file)
    return false if file.arch == 'src' && !mirror_src
    return false if validate_local_file(file)
    return false if deduplicate(file)

    true
  end

  def replace_directory(source_dir, destination_dir)
    old_directory = File.join(File.dirname(destination_dir), '.old_' + File.basename(destination_dir))

    FileUtils.remove_entry(old_directory) if Dir.exist?(old_directory)
    FileUtils.mv(destination_dir, old_directory) if Dir.exist?(destination_dir)
    FileUtils.mv(source_dir, destination_dir)
    FileUtils.chmod(0o755, destination_dir)
  rescue StandardError => e
    raise RMT::Mirror::Exception.new(_('Error while moving directory %{src} to %{dest}: %{error}') % {
      src: source_dir,
      dest: destination_dir,
      error: e.message
    })
  end
end
