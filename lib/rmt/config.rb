require 'config'
require_relative '../rmt'

Config.setup do |config|
  config.merge_nil_values = false

  config.schema do
    required(:scc).schema
  end
end

Config.load_and_set_settings(
  File.join(__dir__, '../../config/default_rmt.yml'),
  '/etc/rmt.conf',
  File.join(__dir__, '../../config/rmt.yml'),
  File.join(__dir__, '../../config/rmt.local.yml')
)

module RMT::Config
  def self.method_missing(key)
    if Settings[key]
      Settings[key]
    else
      super
    end
  end

  def self.respond_to_missing?
    super
  end

  def self.db_config(key = 'database')
    {
      'username' => Settings[key].username,
      'password' => Settings[key].password,
      'database' => Settings[key].database,
      'host'     => Settings[key].host     || 'localhost',
      'adapter'  => Settings[key].adapter  || 'mysql2',
      'encoding' => Settings[key].encoding || 'utf8',
      'timeout'  => Settings[key].timeout  || 5000,
      'pool'     => Settings[key].pool     || 5
    }
  end

  ##
  # This method checks whether or not deduplication should be done by hardlinks.
  # If hardlinks are not used, the file will be copied instead.
  def self.deduplication_by_hardlink?
    Settings.try(:mirroring).try(:dedup_method).to_s.to_sym != :copy
  end
end
