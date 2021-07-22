class RMT::CLI::Import < RMT::CLI::Base

  desc 'data PATH', _('Read SCC data from given path')
  def data(path)
    RMT::Lockfile.lock do
      path = needs_path(path)
      RMT::SCC.new(options).import(path)
    end
  end

  desc 'repos PATH', _('Mirror repos from given path')
  def repos(path)
    RMT::Lockfile.lock do
      path = needs_path(path)

      logger = RMT::Logger.new(STDOUT)
      mirror = RMT::Mirror.new(logger: logger, airgap_mode: true)

      repos_file = File.join(path, 'repos.json')
      raise RMT::CLI::Error.new(_('%{file} does not exist.') % { file: repos_file }) unless File.exist?(repos_file)

      begin
        exported_suma_path = File.join(path, '/suma/')
        suma_repo_url = URI.join('file://', exported_suma_path).to_s
        mirror.mirror_suma_product_tree(repository_url: suma_repo_url)
      rescue RMT::Mirror::Exception => e
        logger.warn(e.message)
      end

      repos = JSON.parse(File.read(repos_file))
      repos.each do |repo_json|
        repo = Repository.find_by(external_url: repo_json['url'])
        if repo.nil?
          warn _('repository by URL %{url} does not exist in database') % { url: repo_json['url'] }
          next
        end

        begin
          exported_repo_path = File.join(path, Repository.make_local_path(repo_json['url']))
          repo_url = URI.join('file://', exported_repo_path).to_s
          mirror.mirror(
            repository_url: repo_url,
            local_path: Repository.make_local_path(repo.external_url),
            auth_token: repo.auth_token,
            repo_name: repo.name,
            do_not_raise: false
          )

          repo.refresh_timestamp!
        rescue RMT::Mirror::Exception => e
          logger.warn e.to_s
        end
      end
    end
  end

end
