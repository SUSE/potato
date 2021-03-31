require 'rails_helper'

RSpec.describe RMT::CLI::Clean do
  describe '#packages' do
    let(:command) { described_class.start(argv) }

    let(:tmp_dir) { Dir.mktmpdir }
    let(:mirror_dir) { File.join(tmp_dir, 'public', 'repo') }

    let(:dummy_repo) do
      { fixture: 'dummy_repo', dir: File.join(mirror_dir, 'dummy_repo') }
    end
    let(:dummy_repo_with_src) do
      { fixture: 'dummy_repo_with_src', dir: File.join(mirror_dir, 'dummy_repo_with_src') }
    end
    let(:stale_rpm_1) do
      { fixture: 'dummy_repo_with_src/x86_64/apples-0.0.2-lp151.2.1.x86_64.rpm',
        file: File.join(dummy_repo_with_src[:dir], 'x86_64', 'lemon-0.0.2-lp151.2.1.x86_64.rpm'),
        size: 7280 }
    end
    let(:stale_drpm_1) do
      { fixture: 'dummy_repo_with_src/x86_64/apples-0.0.1_0.0.2-lp151.2.1.x86_64.drpm',
        file: File.join(dummy_repo_with_src[:dir], 'x86_64', 'lemon-0.0.1_0.0.2-lp151.2.1.x86_64.drpm'),
        size: 3544 }
    end
    let(:stale_rpm_2) do
      { fixture: 'dummy_repo/apples-0.2-0.x86_64.rpm',
        file: File.join(dummy_repo[:dir], 'blueberry-0.2-0.x86_64.rpm'),
        size: 1950 }
    end
    let(:stale_drpm_2) do
      { fixture: 'dummy_repo/apples-0.1-0.x86_64.drpm',
        file: File.join(dummy_repo[:dir], 'blueberry-0.1-0.x86_64.drpm'),
        size: 2088 }
    end
    let(:stale_src_1) do
      { fixture: 'dummy_repo_with_src/src/oranges-0.0.1-lp151.1.1.src.rpm',
        file: File.join(dummy_repo_with_src[:dir], 'src', 'lemon-0.0.1-lp151.1.1.src.rpm'),
        size: 7518 }
    end
    let(:stale_src_2) do
      { fixture: 'dummy_repo_with_src/src/apples-0.0.2-lp151.2.1.src.rpm',
        file: File.join(dummy_repo_with_src[:dir], 'src', 'lemon-0.0.2-lp151.2.1.src.rpm'),
        size: 7528 }
    end

    let(:input) { 'yes' }
    let(:expected_output) do
      <<~OUTPUT
        \n\e[1mScanning the mirror directory for 'repomd.xml' files...\e[0m
        RMT found repomd.xml files: 2 files.
        Now, it will parse all repomd.xml files, search for stale packages on disk and clean them.

        #{confirmation_prompt}#{expected_result_output}
      OUTPUT
    end
    let(:confirmation_prompt) do
      <<~OUTPUT
        \e[1mThis can take several minutes. Would you like to continue and clean staled packages?\e[0m
          Only 'yes' will be accepted.
          \e[1mEnter a value:\e[0m\s
      OUTPUT
    end

    around do |example|
      RMT.send(:remove_const, 'DEFAULT_MIRROR_DIR')
      RMT.const_set('DEFAULT_MIRROR_DIR', mirror_dir)
      FileUtils.mkdir_p(mirror_dir)
      example.run
      FileUtils.rm_r(tmp_dir, secure: false)
    end

    context 'when no repomd files have been found' do
      let(:argv) { ['packages'] }
      let(:expected_output) do
        <<~OUTPUT
          \n\e[1mScanning the mirror directory for 'repomd.xml' files...\e[0m
          \e[31;1mRMT found no repomd.xml files. Check if RMT is properly configured.\e[0m
        OUTPUT
      end

      include_examples 'prints to stdout'
    end

    context "when RMT asks for confirmation and user inputs text other than 'yes'" do
      let(:mirrored_repos) { [dummy_repo, dummy_repo_with_src] }
      let(:expected_result_output) { 'Clean cancelled.' }
      let(:input) { 'no' }

      include_context 'command without options'
      include_context 'mirror directory without stale files'

      include_examples 'prints to stdout'
    end

    context 'when no stale packages have been found' do
      let(:mirrored_repos) { [dummy_repo, dummy_repo_with_src] }
      let(:expected_result_output) { "\e[32;1mNo stale packages have been found!\e[0m" }

      include_context 'mirror directory without stale files'

      context 'and no options have been passed' do
        include_context 'command without options'

        include_examples 'prints to stdout'
        include_examples 'does not remove files'
        include_examples 'does not remove database entries'
      end

      context 'and --verbose option is set' do
        include_context 'command with verbose mode'

        include_examples 'prints to stdout'
        include_examples 'does not remove files'
        include_examples 'does not remove database entries'
      end

      context 'and --non-interactive option is set' do
        include_context 'command with non-interactive mode'

        let(:confirmation_prompt) { '' }

        include_examples 'prints to stdout'
        include_examples 'does not remove files'
        include_examples 'does not remove database entries'
      end
    end

    context 'when there are stale packages' do
      let(:mirrored_repos) { [dummy_repo, dummy_repo_with_src] }
      let(:stale_files) { [stale_rpm_1, stale_drpm_1, stale_rpm_2, stale_drpm_2] }
      let(:stale_database_entries) { [stale_rpm_1, stale_rpm_2, stale_drpm_2] }

      let(:expected_result_output) do
        <<~OUTPUT.chomp
          \e[1mDirectory: #{dummy_repo_with_src[:dir]}\e[0m
          Cleaned 2 files (#{file_human_size(10824)}), 1 database entry.

          \e[1mDirectory: #{dummy_repo[:dir]}\e[0m
          Cleaned 2 files (#{file_human_size(4038)}), 2 database entries.

          #{'-' * 80}
          \e[32;1mTotal: cleaned 4 files (#{file_human_size(14862)}), 3 database entries.\e[0m
        OUTPUT
      end

      context 'and no options have been passed' do
        include_context 'mirror directory with stale files'
        include_context 'database entries for stale files'
        include_context 'command without options'

        include_examples 'prints to stdout'
        include_examples 'remove files'
        include_examples 'remove database entries'
      end

      context 'and --dry-run option is set' do
        include_context 'mirror directory with stale files'
        include_context 'database entries for stale files'
        include_context 'command with dry run option'

        include_examples 'prints to stdout'
        include_examples 'does not remove files'
        include_examples 'does not remove database entries'
      end

      context 'and --verbose option is set' do
        let(:expected_result_output) do
          <<~OUTPUT.chomp
          \e[1mDirectory: #{dummy_repo_with_src[:dir]}\e[0m
            Cleaned 'x86_64/lemon-0.0.1_0.0.2-lp151.2.1.x86_64.drpm' (#{file_human_size(3544)}), 0 database entries.
            Cleaned 'x86_64/lemon-0.0.2-lp151.2.1.x86_64.rpm' (#{file_human_size(7280)}), 1 database entry.
          Cleaned 2 files (#{file_human_size(10824)}), 1 database entry.

          \e[1mDirectory: #{dummy_repo[:dir]}\e[0m
            Cleaned 'blueberry-0.1-0.x86_64.drpm' (#{file_human_size(2088)}), 1 database entry.
            Cleaned 'blueberry-0.2-0.x86_64.rpm' (#{file_human_size(1950)}), 1 database entry.
          Cleaned 2 files (#{file_human_size(4038)}), 2 database entries.

          #{'-' * 80}
          \e[32;1mTotal: cleaned 4 files (#{file_human_size(14862)}), 3 database entries.\e[0m
          OUTPUT
        end

        include_context 'mirror directory with stale files'
        include_context 'database entries for stale files'
        include_context 'command with verbose mode'

        include_examples 'prints to stdout'
        include_examples 'remove files'
        include_examples 'remove database entries'
      end

      context 'and --non-interactive option is set' do
        include_context 'mirror directory with stale files'
        include_context 'database entries for stale files'
        include_context 'command with non-interactive mode'

        include_examples 'prints to stdout'
        include_examples 'remove files'
        include_examples 'remove database entries'
      end

      context 'and there are stale source packages' do
        let(:stale_files) { [stale_src_1, stale_src_2, stale_rpm_1, stale_drpm_1, stale_rpm_2, stale_drpm_2] }
        let(:stale_database_entries) { [stale_rpm_1, stale_rpm_2, stale_drpm_2, stale_src_2] }
        let(:expected_result_output) do
          <<~OUTPUT.chomp
          \e[1mDirectory: #{dummy_repo_with_src[:dir]}\e[0m
            Cleaned 'src/lemon-0.0.1-lp151.1.1.src.rpm' (#{file_human_size(7518)}), 0 database entries.
            Cleaned 'src/lemon-0.0.2-lp151.2.1.src.rpm' (#{file_human_size(7528)}), 1 database entry.
            Cleaned 'x86_64/lemon-0.0.1_0.0.2-lp151.2.1.x86_64.drpm' (#{file_human_size(3544)}), 0 database entries.
            Cleaned 'x86_64/lemon-0.0.2-lp151.2.1.x86_64.rpm' (#{file_human_size(7280)}), 1 database entry.
          Cleaned 4 files (#{file_human_size(25870)}), 2 database entries.

          \e[1mDirectory: #{dummy_repo[:dir]}\e[0m
            Cleaned 'blueberry-0.1-0.x86_64.drpm' (#{file_human_size(2088)}), 1 database entry.
            Cleaned 'blueberry-0.2-0.x86_64.rpm' (#{file_human_size(1950)}), 1 database entry.
          Cleaned 2 files (#{file_human_size(4038)}), 2 database entries.

          #{'-' * 80}
          \e[32;1mTotal: cleaned 6 files (#{file_human_size(29908)}), 4 database entries.\e[0m
          OUTPUT
        end

        include_context 'mirror directory with stale files'
        include_context 'database entries for stale files'
        include_context 'command with verbose mode'

        include_examples 'prints to stdout'
        include_examples 'remove files'
        include_examples 'remove database entries'
      end
    end
  end
end
