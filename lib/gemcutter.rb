class Gemcutter
  if Rails.env.development? || Rails.env.test?
    include Vault::FS
  else
    include Vault::S3
  end

  attr_reader :user, :spec, :message, :code, :rubygem, :body, :version, :version_id, :subdomain

  def initialize(user, body, subdomain_name = 'gemcutter')
    @user = user
    @body = StringIO.new(body.read)
    @subdomain_name = subdomain_name
  end

  def process
    pull_spec && find && authorize && save
  end

  def authorize
    import? ||
    rubygem.pushable? ||
    rubygem.owned_by?(user) ||
    subdomain.try(:belongs_to, user) ||
    notify("You do not have permission to push to this gem.", 403)
  end

  def import?
    user.rubyforge_importer? && version.new_record?
  end

  def save
    if update
      write_gem
      @version_id = self.version.id
      Delayed::Job.enqueue self, 1
      notify("Successfully registered gem: #{self.version.to_title}", 200)
    else
      notify("There was a problem saving your gem: #{rubygem.errors.full_messages}", 403)
    end
  end

  def notify(message, code)
    @message = message
    @code    = code
    false
  end

  def update
    Rubygem.transaction do
      rubygem.build_ownership(user) unless user.try(:rubyforge_importer?)
      rubygem.update_attributes_from_gem_specification!(version, spec)
    end
    true
  rescue ActiveRecord::RecordInvalid, ActiveRecord::Rollback
    false
  end

  def pull_spec
    begin
      format = Gem::Format.from_io(self.body)
      @spec = format.spec
    rescue Exception => e
      notify("Gemcutter cannot process this gem.\n" + 
             "Please try rebuilding it and installing it locally to make sure it's valid.\n" +
             "Error:\n#{e.message}\n#{e.backtrace.join("\n")}", 422)
    end
  end

  def find
    @subdomain = subdomain_for_name(@subdomain_name)
    @rubygem = Rubygem.find_or_initialize_by_name_and_subdomain_id(self.spec.name, @subdomain.try(:id))
    @version = @rubygem.find_or_initialize_version_from_spec(spec)
  end

  def subdomain_for_name(name)
    return nil if name == 'gemcutter'
    subdomain = Subdomain.find_or_create_by_name(name)
    subdomain.users << user if subdomain.users.count.zero?
    subdomain
  end

  def subdomain_name
    @subdomain.try(:name)
  end

  def self.server_path(subdomain_name = nil, *more)
    File.expand_path(File.join(File.dirname(__FILE__), '..', 'server', subdomain_name || '', *more))
  end

  # Overridden so we don't get megabytes of the raw data printing out
  def inspect
    attrs = [:@rubygem, :@user, :@message, :@code].map { |attr| "#{attr}=#{instance_variable_get(attr) || 'nil'}" }
    "<Gemcutter #{attrs.join(' ')}>"
  end

  def self.indexer(subdomain_name = nil)
    indexer = Gem::Indexer.new(Gemcutter.server_path(subdomain_name), :build_legacy => false)
    def indexer.say(message) end
    indexer
  end
end
