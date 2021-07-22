require 'rmt/lockfile'
require 'rmt/cli/decorators'
require 'etc'

class RMT::CLI::Base < Thor

  class << self
    # custom output of the help command
    # (removes the alphabetical sorting and adds some custom behavior)
    def help(shell, subcommand = false)
      list = printable_commands(true, subcommand)

      list.reject! { |l| l[0].split.include?('help') }

      shell.say _('Commands:')

      shell.print_table(list, indent: 2, truncate: true)
      shell.say
      class_options_help(shell)

      shell.say _("Run '%{command}' for more information on a command and its subcommands.") % { command: "#{basename} help [COMMAND]" }

      shell.say
      shell.say _('Do you have any suggestions for improvement? We would love to hear from you!')
      shell.say _('Check out %{url}') % { url: 'https://github.com/SUSE/rmt/issues/new' }
    end

    def dispatch(command, given_args, given_opts, config)
      handle_exceptions { super(command, given_args, given_opts, config) }
    rescue RMT::CLI::Error => e
      warn e.to_s
      if config[:shell]&.base&.options&.[]('debug')
        warn e.cause ? e.cause.inspect : e.inspect
        warn e.cause ? e.cause.backtrace : e.backtrace
      end
      exit e.exit_code # rubocop:disable Rails/Exit
    end

    def handle_exceptions
      yield
    rescue RMT::Deduplicator::HardlinkException => e
      raise RMT::CLI::Error.new(
        _('Could not create deduplication hardlink: %{error}.') % { error: e.message },
        RMT::CLI::Error::ERROR_OTHER
      )
    rescue Mysql2::Error => e
      if e.message =~ /^Access denied/
        raise RMT::CLI::Error.new(
          _("Cannot connect to database server. Ensure its credentials are correctly configured in '%{path}' or configure RMT with YaST ('%{command}').") \
          % {
            path: '/etc/rmt.conf',
            command: 'yast2 rmt'
          },
          RMT::CLI::Error::ERROR_DB
        )
      elsif e.message =~ /^Can't connect/
        raise RMT::CLI::Error.new(
          _("Cannot connect to database server. Make sure it is running and its credentials are configured in '%{path}'.") % { path: '/etc/rmt.conf' },
          RMT::CLI::Error::ERROR_DB
        )
      else
        # Unexpected DB error, not handling it
        raise e
      end
    rescue ActiveRecord::NoDatabaseError
      raise RMT::CLI::Error.new(
        _("The RMT database has not yet been initialized. Run '%{command}' to set up the database.") \
        % { command: 'systemctl start rmt-server-migration.service' },
        RMT::CLI::Error::ERROR_DB
      )
    rescue RMT::SCC::CredentialsError, ::SUSE::Connect::Api::InvalidCredentialsError
      raise RMT::CLI::Error.new(
        _("The SCC credentials are not configured correctly in '%{path}'. You can obtain them from %{url}") % {
          path: '/etc/rmt.conf',
          url: 'https://scc.suse.com'
        },
        RMT::CLI::Error::ERROR_SCC
      )
    rescue RMT::Lockfile::ExecutionLockedError => e
      raise RMT::CLI::Error.new(
        e.message,
        RMT::CLI::Error::ERROR_OTHER
      )
    rescue SUSE::Connect::Api::RequestError => e
      raise RMT::CLI::Error.new(
        _("SCC API request failed. Error details:\nRequest URL: %{url}\nResponse code: %{code}\nResponse body:\n%{body}") % {
          url: e.response.request.url,
          code: e.response.code,
          body: e.response.body
        },
        RMT::CLI::Error::ERROR_OTHER
      )
    end

    # These methods are needed to properly format the hint outputs for `rmt-cli repos custom`. This is a workaround
    # taken and adapted from https://github.com/erikhuda/thor/issues/261, as Thor does not seem to handle nested subcommands
    # the way we expect it to.
    def banner(command, _namespace = nil, _subcommand = false)
      (name == RMT::CLI::Main.name) ? "#{basename} #{command.usage}" : "#{basename} #{subcommand_prefix} #{command.usage}"
    end

    def subcommand_prefix
      name.gsub(/.*::/, '').gsub(/^[A-Z]/) { |match| match[0].downcase }.gsub(/[A-Z]/) { |match| " #{match[0].downcase}" }
    end

    def process_user_name
      Etc.getpwuid(Process.euid).name
    end

  end

  protected

  def logger
    @logger ||= RMT::Logger.new($stdout)
    debug = options[:debug] || Settings&.log_level&.cli == 'debug'
    @logger.level = debug ? Logger::DEBUG : Logger::INFO
    @logger
  end

  private

  def needs_path(path, writable: false)
    # expand the path to make it easier to work with
    path = File.expand_path(path)

    raise RMT::CLI::Error.new(_('%{path} is not a directory.') % { path: path }) unless File.directory?(path)

    if writable
      unless File.writable?(path)
        raise RMT::CLI::Error.new(_('%{path} is not writable by user %{username}.') % {
          path: path,
          username: RMT::CLI::Base.process_user_name
        })
      end
    end

    path
  end

  # Allows to have any type of multi input that you want:
  #
  # 1575 (alone)
  # SLES/15/x86_64,1743 (no space but with comma)
  # SLES/15/x86_64, 1743 (space with comma)
  # SLES/15/x86_64 1743 (space but no comma)
  # "SLES/15/x86_64, 1743, SLED/15" (enclosed in spaces)
  def clean_target_input(input)
    input.inject([]) { |targets, object| targets + object.to_s.split(/,|\s/) }.reject(&:empty?)
  end

end
