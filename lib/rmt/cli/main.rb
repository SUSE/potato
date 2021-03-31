require 'thor'

class RMT::CLI::Main < RMT::CLI::Base

  class_option :debug, desc: _('Enable debug output'), type: :boolean, aliases: '-d', required: false

  desc 'sync', _('Sync database with SUSE Customer Center')
  def sync
    RMT::Lockfile.lock do
      RMT::SCC.new(options).sync
    end
  end

  desc 'products', _('List and modify products')
  subcommand 'products', RMT::CLI::Products

  desc 'repos', _('List and modify repositories')
  subcommand 'repos', RMT::CLI::Repos

  desc 'mirror', _('Mirror repositories')
  subcommand 'mirror', RMT::CLI::Mirror

  desc 'import', _('Import commands for Offline Sync')
  subcommand 'import', RMT::CLI::Import

  desc 'export', _('Export commands for Offline Sync')
  subcommand 'export', RMT::CLI::Export

  desc 'systems', _('List and manipulate registered systems')
  subcommand 'systems', RMT::CLI::Systems

  desc 'clean', _('Clean files')
  subcommand 'clean', RMT::CLI::Clean

  desc 'version', _('Show RMT version')
  def version
    puts RMT::VERSION
  end

  map %w[--version -v] => :version

  def self.exit_on_failure?
    true
  end
end
