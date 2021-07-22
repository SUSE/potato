require 'rails_helper'

describe RMT::CLI::Import, :with_fakefs do
  let(:path) { '/mnt/usb' }

  describe 'data' do
    include_examples 'handles non-existing path'
    include_examples 'handles lockfile exception'

    subject(:command) { described_class.start(['data', path]) }

    it 'triggers import to path' do
      FileUtils.mkdir_p path

      expect_any_instance_of(RMT::SCC).to receive(:import).with(path)
      command
    end

    context 'with unexpected error being raised' do
      it 'removes lockfile and re-raises error' do
        FileUtils.mkdir_p path
        allow_any_instance_of(RMT::SCC).to receive(:import).with(path).and_raise(RuntimeError)

        expect { command }.to raise_error(RuntimeError)
      end
    end

    context 'with relative path' do
      let(:path) { '/mnt/usb/../usb' }

      it 'triggers import to path' do
        FileUtils.mkdir_p path

        expect_any_instance_of(RMT::SCC).to receive(:import).with('/mnt/usb')
        command
      end
    end
  end

  describe 'repos' do
    include_examples 'handles non-existing path'
    include_examples 'handles lockfile exception'

    subject(:command) { described_class.start(['repos', path]) }

    let(:repo1) { create :repository, mirroring_enabled: true, auth_token: 'foobar' }
    let(:repo2) { create :repository, mirroring_enabled: true }
    let(:repo1_local_path) { repo_url_to_local_path(path, repo1.external_url) }
    let(:repo2_local_path) { repo_url_to_local_path(path, repo2.external_url) }
    let(:mirror_double) { instance_double RMT::Mirror }
    let(:repo_settings) do
      [
        { url: repo1.external_url, auth_token: repo1.auth_token.to_s },
        { url: repo2.external_url, auth_token: repo2.auth_token.to_s }
      ]
    end

    it 'mirrors repo1 and repo2' do
      FileUtils.mkdir_p path
      File.write("#{path}/repos.json", repo_settings.to_json)

      expect(RMT::Mirror).to receive(:new).with(
        logger: instance_of(RMT::Logger),
        airgap_mode: true
      ).and_return(mirror_double)

      expect(mirror_double).to receive(:mirror_suma_product_tree)
      expect(mirror_double).to receive(:mirror).with(
        repository_url: repo1_local_path,
        local_path: Repository.make_local_path(repo1.external_url),
        auth_token: repo1.auth_token,
        repo_name: repo1.name,
        do_not_raise: false
      )

      expect(mirror_double).to receive(:mirror).with(
        repository_url: repo2_local_path,
        local_path: Repository.make_local_path(repo2.external_url),
        auth_token: repo2.auth_token,
        repo_name: repo2.name,
        do_not_raise: false
      )

      command
    end

    context 'with relative path' do
      let(:path) { '/mnt/usb/../usb' }
      let(:repo1_local_path) { repo_url_to_local_path('/mnt/usb', repo1.external_url) }
      let(:repo2_local_path) { repo_url_to_local_path('/mnt/usb', repo2.external_url) }

      it 'mirrors repo1 and repo2' do
        FileUtils.mkdir_p path
        File.write("#{path}/repos.json", repo_settings.to_json)

        expect(RMT::Mirror).to receive(:new).with(
          logger: instance_of(RMT::Logger),
          airgap_mode: true
        ).and_return(mirror_double)

        expect(mirror_double).to receive(:mirror_suma_product_tree)
        expect(mirror_double).to receive(:mirror).with(
          repository_url: repo1_local_path,
          local_path: Repository.make_local_path(repo1.external_url),
          auth_token: repo1.auth_token,
          repo_name: repo1.name,
          do_not_raise: false
        )

        expect(mirror_double).to receive(:mirror).with(
          repository_url: repo2_local_path,
          local_path: Repository.make_local_path(repo2.external_url),
          auth_token: repo2.auth_token,
          repo_name: repo2.name,
          do_not_raise: false
        )

        command
      end
    end

    context 'no repos.json file' do
      it 'warns that repos.json does not exist' do
        FileUtils.mkdir_p path
        expect { command }.to raise_error(SystemExit).and output('').to_stdout.and output(/repos.json does not exist/).to_stderr
      end
    end

    context 'suma product tree mirror with exception' do
      it 'outputs exception message' do
        expect_any_instance_of(RMT::Mirror).to receive(:mirror_suma_product_tree).and_raise(RMT::Mirror::Exception, 'black mirror')
        expect_any_instance_of(RMT::Mirror).to receive(:mirror).twice

        FileUtils.mkdir_p path
        File.write("#{path}/repos.json", repo_settings.to_json)

        expect_any_instance_of(RMT::Logger).to receive(:warn).with('black mirror')
        command
      end
    end

    context 'repository does not exist in database' do
      let(:missing_repo_url) { 'http://foo.bar.missing/repo/bar' }
      let(:missing_local_path) { repo_url_to_local_path(path, missing_repo_url) }
      let(:repo_settings) do
        [
          { url: missing_repo_url, auth_token: '' }
        ]
      end

      it 'tries to mirrors repo2, but outputs warning' do
        FileUtils.mkdir_p path
        File.write("#{path}/repos.json", repo_settings.to_json)

        expect_any_instance_of(RMT::Mirror).to receive(:mirror_suma_product_tree)
        expect { command }.to output(/repository by URL #{missing_repo_url} does not exist in database/).to_stderr.and output('').to_stdout
      end
    end

    context 'with exceptions during mirroring' do
      let(:repo_settings) do
        [
          { url: repo1.external_url, auth_token: repo1.auth_token.to_s },
          { url: repo2.external_url, auth_token: repo2.auth_token.to_s }
        ]
      end

      it 'mirrors repo2 when repo1 raised an exception' do
        FileUtils.mkdir_p path
        File.write("#{path}/repos.json", repo_settings.to_json)

        expect(RMT::Mirror).to receive(:new).with(
          logger: instance_of(RMT::Logger),
          airgap_mode: true
        ).and_return(mirror_double)

        expect(mirror_double).to receive(:mirror_suma_product_tree)
        expect(mirror_double).to receive(:mirror).with(
          repository_url: repo1_local_path,
          local_path: Repository.make_local_path(repo1.external_url),
          auth_token: repo1.auth_token,
          repo_name: repo1.name,
          do_not_raise: false
        ).and_raise(RMT::Mirror::Exception, 'black mirror')

        expect(mirror_double).to receive(:mirror).with(
          repository_url: repo2_local_path,
          local_path: Repository.make_local_path(repo2.external_url),
          auth_token: repo2.auth_token,
          repo_name: repo2.name,
          do_not_raise: false
        )

        expect_any_instance_of(RMT::Logger).to receive(:warn).with('black mirror')

        command
      end
    end
  end
end
