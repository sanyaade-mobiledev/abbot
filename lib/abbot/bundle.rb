module Abbot
  
  class Bundle
    
    ######################################################
    ## CONSTANTS
    ##
    LONG_LANGUAGE_MAP = { :english => :en, :french => :fr, :german => :de, :japanese => :ja, :spanish => :es, :italian => :it }
    SHORT_LANGUAGE_MAP = { :en => :english, :fr => :french, :de => :german, :ja => :japanese, :es => :spanish, :it => :italian }

    # Creates a new bundle with the passed options.  You must include at 
    # least the source_root, the bundle_type, and a parent_bundle, if you
    # have one.
    #
    # The :next_bundle option is used internally to setup bundles in the load
    # path.  Normally you should not pass this option so that it can be filled
    # in for you.
    # 
    # === Options
    #  :source_root:: The path to the bundle source
    #  :bundle_type:: the bundle type.  must be :framework, :app, :library
    #  :parent_bundle:: the parent bundle.  must be included except for :library
    #
    def initialize(opts={}) 
      @source_root = opts[:source_root]
      @parent_bundle = opts[:parent_bundle]
      @bundle_type = (opts[:bundle_type] || :library).to_sym 
      
      # ensure consistency
      raise "bundle must include source_root (opts=#{opts})" if @source_root.nil?

      if @bundle_type == :library
        raise "library bundle may not have parent bundle" if @parent_bundle
      else
        raise "#{@bundle_type} bundle must have parent bundle" if @parent_bundle.nil?
      end

    end

    ######################################################
    ## GLOBAL CONFIG
    ##
    
    # === Returns
    # true if the passed path appears to be a bundle
    def self.is_bundle?(path)
      %w(sc-config sc-config.rb sc-config.yaml).each do |filename|
        return true if File.exist?(File.join(path, filename))
      end
      return false
    end
    
    ######################################################
    ## CORE PROPERTIES
    ##
    ## These are the core properties that all other extended properties are
    ## computed from.

    # Returns true only if this bundle represents a library library.  
    # Generally false
    def is_library?
      bundle_type == :library 
    end

    # The full path to the source root of the bundle
    def source_root; @source_root; end

    # The bundle's parent bundle.  All bundles have a parent bundle except for
    # a library bundle.
    def parent_bundle; @parent_bundle; end

    # Returns the type of bundle.  Must be :library, :framework, :app
    def bundle_type; @bundle_type; end

    # The name of the bundle as it can be referenced in code.  The bundle name
    # is composed of the bundlename itself + its parent bundle name unless the
    # parent is a library.
    def bundle_name
      return @bundle_name unless @bundle_name.nil? && bundle_type != :library
      @bundle_name = File.basename(self.source_root)
      
      unless parent_bundle.nil? || parent_bundle.is_library?
        @bundle_name = [parent_bundle.bundle_name, @bundle_name].join('/')
      end
      @bundle_name = @bundle_name.to_sym
      return @bundle_name
    end 

    # Returns the environment for the current bundle.  The environments is
    # computed by taked the merge config settings and merging the all config
    # with any config for the current bundle
    # 
    # The environment is computed by merging the sc-config settings for all
    # roots in the path.  Then the bundle-specific configs are merged on top
    # of the global configs.  Finally, any environmental configs (set in 
    # Abbot::env) are merged over top.
    #
    def environment
      return @environment unless @environment.nil?

      # get current mode
      mode_name = Abbot.env[:mode] || :debug
      mode_name = :debug if (mode_name == :development) 

      ret = merged_sc_config_for(:all, :all)
      
      ret.merge! merged_sc_config_for(:all, mode_name)
      ret.merge! merged_sc_config_for(bundle_name, :all)

      ret.merge! merged_sc_config_for(bundle_name, mode_name)
      ret.merge! Abbot.env
      
      @environment = ret 
    end

    # Returns a manifest that describes every resource in the bundle.  The
    # manifest is generated by executing a Filter called abbot:manifest:build
    # 
    # You can define your own filters in your sc-config or in ruby files that
    # you load from your sc-config.
    def manifest
      @manifest ||= Manifest.new(:bundle => self).prepare!
    end
    
    ######################################################
    ## CHILD BUNDLE METHODS
    ##

    # Returns bundles for all apps installed in this bundle
    def app_bundles
      @app_bundles ||= app_paths.map do |p| 
        Bundle.new :parent_bundle => self, :source_root => p, :bundle_type => :app
      end
    end
    
    # Returns the bundles for all frameworks installed in this bundle
    def framework_bundles
      @framework_bundles ||= framework_paths.map do |p|
        Bundle.new :parent_bundle => self, :source_root => p, :bundle_type => :framework
      end
    end
    
    # Returns all bundles installed in this bundle.  
    def child_bundles
      [app_bundles, framework_bundles].flatten.compact.sort do |a,b|
        a.source_root <=> b.source_root
      end
    end
    
    # Returns all bundles, including bundles from children and from other 
    # libraries in the load path, if there are any
    def all_bundles
      ret = [child_bundles]
      child_bundles.each { |b| ret += b.all_bundles }
      ret.flatten.compact.sort { |a,b| a.source_root <=> b.source_root }
    end
      
    ######################################################
    ## INTERNAL SUPPORT METHODS
    ##
    #protected 
    
    # Returns the paths for all applications installed in this bundle.
    def app_paths
      return @app_paths unless @app_paths.nil?
      
      ret = []

      # check for presence of 'clients' directory
      path = File.expand_path(File.join(source_root, 'clients'))
      ret += Dir.glob(File.join(path, '*')) if File.exist?(path)

      # check for presence of 'apps' directory
      path = File.expand_path(File.join(source_root, 'apps'))
      ret += Dir.glob(File.join(path, '*')) if File.exist?(path)
      
      @app_paths = ret.flatten.uniq.compact.sort.reject do |path|  
        !File.directory?(path)
      end
    end 

    # Returns the paths for all frameworks installed in this bundle
    def framework_paths
      return @framework_paths unless @framework_paths.nil?
      ret = []
      
      # check for presence of 'frameworks' directory
      path = File.expand_path(File.join(source_root, 'frameworks'))
      ret = Dir.glob(File.join(path, '*')) if File.exist?(path)
      ret.reject! { |path| !File.directory?(path) }

      @framework_paths = ret.flatten.uniq.compact.sort.reject do |path|  
        !File.directory?(path)
      end
    end 
    
    # Local config settings loaded from the config file.  Generally you will
    # not want to use this config directly.  Instead, get the environment,
    # which is combined from the parent.
    def local_sc_config
      @local_sc_config ||= Config.load(source_root)
    end
    
    # Merged config settings.  This will take the parent bundle config 
    # settings and merge them into the local config.  Generally you will not 
    # want to use this config directly.  Instead get the environment.
    def merged_sc_config
      return @merged_sc_config unless @merged_sc_config.nil?
      if parent_bundle.nil?
        @merged_sc_config = local_sc_config
      else
        @merged_sc_config = Config.merge_config(parent_bundle.merged_sc_config, local_sc_config)
      end
      
      @merged_sc_config
    end
      
    # Returns the merged config setting for the specified bundle key or 
    # returns an empty hash.
    def merged_sc_config_for(hash_name, mode_name = :all) 
      ret = merged_sc_config["mode(#{mode_name})".to_sym]
      return ret.nil? ? {} : (ret["config(#{hash_name})".to_sym] || {})
    end
    
  end
  
end
