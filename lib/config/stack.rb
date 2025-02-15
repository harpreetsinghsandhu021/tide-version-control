require "pathname"
require_relative "../config"

  # The Stack class manages multiple git configuration files in order of precedence
  # Local config overrides global config, which overrides system config
  class Stack 
    # Path to the user's global git configuration file
    GLOABAL_CONFIG = File.expand_path("~/.gitconfig")
    # Path to the system-wide git configuration file
    SYSTEM_CONFIG = "etc/gitconfig"

    # Initializes a new configuration stack with local, global and system configs
    # @param git_path [Pathname] The path to the git repository
    def initialize(git_path)
      puts git_path
      @configs = {
        :local => Config.new(git_path.join("config")), 
        :global => Config.new(Pathname.new(GLOABAL_CONFIG)), 
        :system => Config.new(Pathname.new(SYSTEM_CONFIG))
      }
    end

    # Opens all configuration files in the stack
    def open
      @configs.each_value(&:open)
    end

    # Retrieves the last (highest priority) value for a given key
    # @param key [String] The configuration key to look up
    # @return [String, nil] The value for the key or nil if not found
    def get(key)
      get_all(key).last
    end

    # Retrieves all values for a given key across all config files
    # @param key [String] The configuration key to look up
    # @return [Array] List of all matching values in precedence order
    def get_all(key)
      [:system, :global, :local].flat_map do |name|
        @configs[name].open
        @configs[name].get_all(key)
      end
    end

    # Returns a Config object for the specified configuration level
    # @param name [Symbol] The configuration level (:system, :global, :local)
    # @return [Config] The configuration object
    def file(name)
      if @configs.has_key?(name)
        @configs[name]
      else
        Config.new(Pathname.new(name))
      end
    end

  
  end