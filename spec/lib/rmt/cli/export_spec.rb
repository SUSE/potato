require 'rails_helper'

describe RMT::CLI::Export, :with_fakefs do
  let(:path) { '/mnt/usb' }

  describe 'settings' do
    include_examples 'handles non-existing path'
    include_examples 'handles non-writable path'
    let(:repository) { create :repository, mirroring_enabled: true, id: 123 }
    let(:command) { described_class.start(['settings', path]) }

    before do
      repository
      create :repository, mirroring_enabled: false
    end

    it 'writes ids of enabled repos to file' do
      FileUtils.mkdir_p path
      expect { command }.to output(/Settings saved at #{path}/).to_stdout
      expected_filename = File.join(path, 'repos.json')
      expected_json = [{ url: repository.external_url, auth_token: repository.auth_token.to_s }].to_json
      expect(File.exist?(expected_filename)).to be true
      expect(File.read(expected_filename).chomp).to eq expected_json
    end

    context 'relative path' do
      let(:path) { '/mnt/usb/../usb' }

      it 'writes ids of enabled repos to file' do
        FileUtils.mkdir_p path
        expect { command }.to output(%r{Settings saved at /mnt/usb}).to_stdout
        expected_filename = File.join('/mnt/usb', 'repos.json')
        expected_json = [{ url: repository.external_url, auth_token: repository.auth_token.to_s }].to_json
        expect(File.exist?(expected_filename)).to be true
        expect(File.read(expected_filename).chomp).to eq expected_json
      end
    end
  end

  describe 'data' do
    include_examples 'handles non-existing path'
    include_examples 'handles non-writable path'

    let(:command) { described_class.start(['data', path]) }

    it 'triggers export to path' do
      FileUtils.mkdir_p path

      expect_any_instance_of(RMT::SCC).to receive(:export).with(path)
      command
    end

    context 'relative path' do
      let(:path) { '/mnt/usb/../usb' }

      it 'triggers export to path' do
        FileUtils.mkdir_p path

        expect_any_instance_of(RMT::SCC).to receive(:export).with('/mnt/usb')
        command
      end
    end
  end

  describe 'repos' do
    include_examples 'handles non-existing path'
    include_examples 'handles non-writable path'

    let(:command) { described_class.start(['repos', path]) }
    let(:mirror_double) { instance_double('RMT::Mirror') }
    let(:repo_settings) do
      [
        { url: 'http://foo.bar/repo1', auth_token: 'foobar' },
        { url: 'http://foo.bar/repo2', auth_token: '' }
      ]
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

    context 'with missing repos.json file' do
      it 'outputs a warning' do
        FileUtils.mkdir_p path

        expect_any_instance_of(RMT::Mirror).to receive(:mirror_suma_product_tree)
        expect { command }.to raise_error(SystemExit).and(output("#{File.join(path, 'repos.json')} does not exist.\n").to_stderr)
      end
    end

    context 'with relative path' do
      let(:path) { '/mnt/usb/../usb' }

      before do
        expect(RMT::Mirror).to receive(:new).with(
          mirroring_base_dir: '/mnt/usb',
          logger: instance_of(RMT::Logger),
          airgap_mode: true
        ).once.and_return(mirror_double)
      end

      it 'reads repo ids from file at path and mirrors these repos' do
        FileUtils.mkdir_p path
        File.write('/mnt/usb/repos.json', repo_settings.to_json)

        expect(mirror_double).to receive(:mirror_suma_product_tree)
        expect(mirror_double).to receive(:mirror).with(
          repository_url: 'http://foo.bar/repo1',
          auth_token: 'foobar',
          local_path: '/repo1',
          do_not_raise: false
        )

        expect(mirror_double).to receive(:mirror).with(
          repository_url: 'http://foo.bar/repo2',
          auth_token: '',
          do_not_raise: false,
          local_path: '/repo2'
        )

        command
      end
    end

    context 'with valid repo ids' do
      before do
        expect(RMT::Mirror).to receive(:new).with(
          mirroring_base_dir: path,
          logger: instance_of(RMT::Logger),
          airgap_mode: true
        ).once.and_return(mirror_double)
      end

      it 'reads repo ids from file at path and mirrors these repos' do
        FileUtils.mkdir_p path
        File.write("#{path}/repos.json", repo_settings.to_json)

        expect(mirror_double).to receive(:mirror_suma_product_tree)
        expect(mirror_double).to receive(:mirror).with(
          repository_url: 'http://foo.bar/repo1',
          auth_token: 'foobar',
          local_path: '/repo1',
          do_not_raise: false
        )

        expect(mirror_double).to receive(:mirror).with(
          repository_url: 'http://foo.bar/repo2',
          auth_token: '',
          local_path: '/repo2',
          do_not_raise: false
        )

        command
      end

      context 'with exceptions during mirroring' do
        it 'outputs exception message' do
          FileUtils.mkdir_p path
          File.write("#{path}/repos.json", repo_settings.to_json)

          expect(mirror_double).to receive(:mirror_suma_product_tree).with({ repository_url: 'https://scc.suse.com/suma/' })
          expect(mirror_double).to receive(:mirror).with(
            repository_url: 'http://foo.bar/repo1',
            auth_token: 'foobar',
            local_path: '/repo1',
            do_not_raise: false
          ).and_raise(RMT::Mirror::Exception, 'black mirror')

          expect(mirror_double).to receive(:mirror).with(
            repository_url: 'http://foo.bar/repo2',
            auth_token: '',
            local_path: '/repo2',
            do_not_raise: false
          )

          expect { command }.to output(/black mirror/).to_stderr
        end
      end
    end
  end
end
