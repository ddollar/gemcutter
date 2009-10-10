module Vault
  module S3
    OPTIONS = {:authenticated => false, :access => :public_read}

    def perform
      Version.update_all({:indexed => true}, {:id => self.version_id})
      update_index
    end

    def specs_index
      Version.subdomain(subdomain_name).with_indexed.map(&:to_index)
    end

    def latest_index
      Version.subdomain(subdomain_name).latest.release.map(&:to_index)
    end

    def prerelease_index
      Version.subdomain(subdomain_name).prerelease.map(&:to_index)
    end

    def write_gem
      cache_path = "#{subdomain_name}/gems/#{spec.original_name}.gem"
      VaultObject.store(cache_path, body.string, OPTIONS)

      quick_path = "#{subdomain_name}/quick/Marshal.#{Gem.marshal_version}/#{spec.original_name}.gemspec.rz"
      Gemcutter.indexer(subdomain_name).abbreviate spec
      Gemcutter.indexer(subdomain_name).sanitize spec
      VaultObject.store(quick_path, Gem.deflate(Marshal.dump(spec)), OPTIONS)
    end

    def update_index
      upload("#{subdomain_name}/specs.#{Gem.marshal_version}.gz", specs_index)
      upload("#{subdomain_name}/latest_specs.#{Gem.marshal_version}.gz", latest_index)
      upload("#{subdomain_name}/prerelease_specs.#{Gem.marshal_version}.gz", prerelease_index)
    end

    def upload(key, value)
      final = StringIO.new
      gzip = Zlib::GzipWriter.new(final)
      gzip.write(Marshal.dump(value))
      gzip.close

      # For the life of me, I can't figure out how to pass a stream in here from a closed StringIO
      VaultObject.store(key, final.string, OPTIONS)
    end
  end

  module FS
    def perform
      write_gem
      update_index
    end

    def source_path
      Gemcutter.server_path(subdomain_name, "source_index")
    end

    def source_index
      if File.exists?(source_path)
        @source_index ||= Marshal.load(Gem.inflate(File.read(source_path)))
      else
        @source_index ||= Gem::SourceIndex.new
      end
    end

    def write_gem
      cache_path = Gemcutter.server_path(subdomain_name, 'gems', "#{spec.original_name}.gem")
      FileUtils.mkdir_p(File.dirname(cache_path))
      File.open(cache_path, "wb") do |f|
        f.write body.string
      end
      File.chmod 0644, cache_path

      quick_path = Gemcutter.server_path(subdomain_name, "quick", "Marshal.#{Gem.marshal_version}", "#{spec.original_name}.gemspec.rz")
      FileUtils.mkdir_p(File.dirname(quick_path))

      Gemcutter.indexer(subdomain_name).abbreviate spec
      Gemcutter.indexer(subdomain_name).sanitize spec
      File.open(quick_path, "wb") do |f|
        f.write Gem.deflate(Marshal.dump(spec))
      end
      File.chmod 0644, quick_path
    end

    def update_index
      source_index.add_spec spec, spec.original_name
      File.open(source_path, "wb") do |f|
        f.write Gem.deflate(Marshal.dump(source_index))
      end

      Gemcutter.indexer(subdomain_name).update_index(source_index)
    end
  end
end
