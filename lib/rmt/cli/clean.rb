class RMT::CLI::Clean < RMT::CLI::Base

  desc 'packages', _('Clean stale package files, based on current repository data.')
  option :non_interactive, aliases: '-n', type: :boolean,
    desc: _('Do not ask anything, use default answers automatically. Default: false')
  option :dry_run, type: :boolean,
    desc: _('Run the clean process without actually removing files.')
  option :verbose, aliases: '-v', type: :boolean,
    desc: _('List files during the cleaning process.')
  long_desc _(
    <<~PACKAGES
    Clean stale package files, based on current repository metadata.

    This command scans the mirror directory for 'repomd.xml' files, parse the
    metadata files, and compare their content with files on disk. Files not
    listed in the metadata are considered stale.

    Then, it removes all stale files from %{test} disk and any associated database entries.
    PACKAGES
  )

  def packages
    print "\n\e[1m"
    print _("Scanning the mirror directory for 'repomd.xml' files...")
    print "\e[0m\n"

    repomd_files = Dir.glob(File.join(RMT::DEFAULT_MIRROR_DIR, '**', 'repomd.xml'))

    repomd_count = repomd_files.count
    if repomd_count == 0
      print "\e[31;1m"
      print _('RMT found no repomd.xml files. Check if RMT is properly configured.')
      print "\e[0m\n"

      return
    end

    repomd_count_text = file_count_text(repomd_count)
    puts _('RMT found repomd.xml files: %{repomd_count}.') % { repomd_count: repomd_count_text }
    puts _('Now, it will parse all repomd.xml files, search for stale packages on disk and clean them.')

    unless options.non_interactive
      print "\n\e[1m"
      print _('This can take several minutes. Would you like to continue and clean staled packages?')
      print "\e[0m\n\s\s"
      print _("Only '%{input}' will be accepted.") % { input: _('yes') }
      print "\n\s\s\e[1m"
      print _('Enter a value:')
      print "\e[0m\s"

      input = $stdin.gets.to_s.strip
      if input != _('yes')
        puts "\n" + _('Clean cancelled.')
        return
      end
    end

    report = run_package_clean(repomd_files)

    if report[:total_cleaned_count] == 0
      print "\n\e[32;1m"
      print _('No stale packages have been found!')
      print "\e[0m\n"

      return
    end

    puts "\n" + '-' * 80
    print "\e[32;1m"
    print _('Total: cleaned %{total_count} (%{total_size}), %{total_db_entries}.') % {
      total_count: file_count_text(report[:total_cleaned_count]),
      total_size: ActiveSupport::NumberHelper.number_to_human_size(report[:total_cleaned_size]),
      total_db_entries: db_entries_text(report[:total_cleaned_db_entries])
    }
    print "\e[0m\n"
  end

  private

  def run_package_clean(repomd_files)
    dirs_with_stale_files = repomd_files.lazy.map do |repomd_file|
      repo_base_dir = File.absolute_path(File.join(File.dirname(repomd_file), '..'))
      stale_packages = stale_packages_list(repo_base_dir, repomd_file)

      next nil if stale_packages.empty?

      [repo_base_dir, stale_packages]
    end.reject(&:nil?)

    stats = dirs_with_stale_files.map do |(repo_base_dir, stale_packages)|
      print "\n\e[1m"
      print _('Directory: %{dir}') % { dir: repo_base_dir }
      print "\e[0m\n"

      partial_stats = clean_stale_packages(stale_packages, repo_base_dir)

      cleaned_files_count = partial_stats.count
      cleaned_files_size, cleaned_db_entries =
        partial_stats.transpose.map { |x| x.reduce(:+) }

      puts _('Cleaned %{file_count_text} (%{total_size}), %{db_entries}.') % {
        file_count_text: file_count_text(cleaned_files_count),
        total_size: ActiveSupport::NumberHelper.number_to_human_size(cleaned_files_size),
        db_entries: db_entries_text(cleaned_db_entries)
      }

      [cleaned_files_count, cleaned_files_size, cleaned_db_entries]
    end

    total_cleaned_count, total_cleaned_size, total_cleaned_db_entries =
      stats.force.transpose.map { |x| x.reduce(:+) }

    {
      total_cleaned_size: total_cleaned_size.to_i,
      total_cleaned_count: total_cleaned_count.to_i,
      total_cleaned_db_entries: total_cleaned_db_entries.to_i
    }
  end

  def stale_packages_list(repo_base_dir, repomd_file)
    expected_packages = parse_packages_data(repomd_file, repo_base_dir)
      .map { |file| File.join(repo_base_dir, file.location) }.sort

    actual_packages = Dir.glob(File.join(repo_base_dir, '**', '*.{rpm,drpm}')).sort

    (actual_packages - expected_packages).sort
  end

  def parse_packages_data(repomd_file, repo_base_dir)
    metadata_files = RepomdParser::RepomdXmlParser.new(repomd_file).parse

    xml_parsers = { deltainfo: RepomdParser::DeltainfoXmlParser,
                    primary: RepomdParser::PrimaryXmlParser }

    metadata_files.reduce([]) do |acc, metadata|
      next acc unless xml_parsers.key?(metadata.type)

      metadata_path = File.join(repo_base_dir, metadata.location)
      acc << xml_parsers[metadata.type].new(metadata_path).parse
    end.flatten
  end

  def clean_stale_packages(packages, repo_base_dir)
    quoted_repo_base_dir = Regexp.quote(repo_base_dir)

    packages.map do |file|
      next nil unless File.exist?(file)

      file_size, db_entries = clean_package(file)

      if options.verbose
        puts "\s\s" + _("Cleaned '%{file_name}' (%{file_size}), %{db_entries}.") % {
          file_name: file.gsub(%r{^#{quoted_repo_base_dir}/?}, ''),
          file_size: ActiveSupport::NumberHelper.number_to_human_size(file_size),
          db_entries: db_entries_text(db_entries)
        }
      end

      [file_size, db_entries]
    end.reject(&:nil?)
  end

  def clean_package(file)
    file_size = File.size(file)
    db_entries = DownloadedFile.where(local_path: file)

    unless options.dry_run
      FileUtils.rm(file)
      db_entries = db_entries.destroy_all
    end

    [file_size, db_entries.count]
  end

  def file_count_text(count)
    n_('%{count} file', '%{count} files', count) % { count: count }
  end

  def db_entries_text(count)
    n_('%{db_entries} database entry', '%{db_entries} database entries', count) % { db_entries: count }
  end
end
