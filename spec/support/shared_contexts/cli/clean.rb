shared_context 'command without options' do
  let(:argv) { ['packages'] }

  around do |example|
    $stdin = StringIO.new("#{input}\n\n")
    example.run
    $stdin = STDIN
  end
end

shared_context 'command with dry run option' do
  let(:argv) { ['packages', '--dry-run'] }

  around do |example|
    $stdin = StringIO.new("#{input}\n\n")
    example.run
    $stdin = STDIN
  end
end

shared_context 'command with verbose mode' do
  let(:argv) { ['packages', '--verbose'] }

  around do |example|
    $stdin = StringIO.new("#{input}\n\n")
    example.run
    $stdin = STDIN
  end
end

shared_context 'command with non-interactive mode' do
  let(:argv) { ['packages', '--non-interactive'] }
  let(:confirmation_prompt) { '' }
end

shared_context 'mirror directory without stale files' do
  before do
    mirrored_repos.each do |repo|
      FileUtils.mkdir_p(repo[:dir])
      FileUtils.cp_r(file_fixture(repo[:fixture]).to_s, mirror_dir)
    end
  end
end

shared_context 'mirror directory with stale files' do
  before do
    mirrored_repos.each do |repo|
      FileUtils.mkdir_p(repo[:dir])
      FileUtils.cp_r(file_fixture(repo[:fixture]).to_s, mirror_dir)

      Dir.glob(File.join(repo[:dir], '**', '*.{rpm,drpm}')).each do |file|
        DownloadedFile.create(
          checksum: SecureRandom.uuid,
          checksum_type: :uuid,
          local_path: file,
          size: File.size(file)
        )
      end
    end

    stale_files.each do |file|
      FileUtils.cp(file_fixture(file[:fixture]).to_s, file[:file])
    end
  end
end

shared_context 'database entries for stale files' do
  before do
    stale_database_entries.each do |file|
      DownloadedFile.create(
        checksum: SecureRandom.uuid,
        checksum_type: :uuid,
        local_path: file[:file],
        size: file[:size]
      )
    end
  end
end
