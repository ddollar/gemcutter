class Version < ActiveRecord::Base
  include Pacecar

  default_scope :order => 'position'

  belongs_to :rubygem, :counter_cache => true
  has_many :dependencies, :dependent => :destroy
  has_many :downloads, :dependent => :destroy

  validates_format_of :number, :with => /^#{Gem::Version::VERSION_PATTERN}$/

  named_scope :owned_by, lambda { |user|
    { :conditions => { :rubygem_id => user.rubygem_ids } }
  }

  named_scope :subscribed_to_by, lambda { |user|
    { :conditions => { :rubygem_id => user.subscribed_gem_ids } }
  }

  named_scope :with_associated, { :conditions => ["rubygems.versions_count > 1"], :include => :rubygem, :order => "versions.built_at desc" }
  named_scope :latest,          { :conditions => { :position   => 0     }, :include => :rubygem }
  named_scope :prerelease,      { :conditions => { :prerelease => true  }}
  named_scope :release,         { :conditions => { :prerelease => false }}

  named_scope :default_subdomain, {
    :include    => :rubygem,
    :conditions => { "rubygems.subdomain_id" => nil }
  }

  named_scope :subdomain, lambda { |subdomain| {
    :include    => { :rubygem => :subdomain },
    :conditions => { "subdomains.name" => subdomain }
  }}

  before_save :update_prerelease
  after_save  :reorder_versions

  def validate
    if new_record? && Version.exists?(:rubygem_id => rubygem_id, :number => number, :platform => platform)
      errors.add_to_base("A version already exists with this number or platform.")
    end
  end

  def self.with_indexed
    all(:conditions => {:indexed => true}, :include => :rubygem, :order => "rubygems.name asc, number asc, built_at asc")
  end

  def self.updated(limit=5)
    built_at_before(DateTime.now.utc).with_associated.limited(limit)
  end

  def self.published(limit=5)
    created_at_before(DateTime.now.utc).by_created_at(:desc).limited(limit)
  end

  def self.find_from_slug!(rubygem_id, slug)
    number, *raw_platform = slug.split('-')
    platform = raw_platform.blank? ? "ruby" : raw_platform.join('-')

    find_by_rubygem_id_and_number_and_platform!(rubygem_id, number, platform)
  end

  def to_s
    number
  end

  def to_title
    "#{rubygem.name} (#{to_s})"
  end

  def to_slug
    param = number.dup
    param << "-#{platform}" if platformed?
    param
  end

  def platformed?
    platform != "ruby"
  end

  def update_prerelease
    self[:prerelease] = to_gem_version.prerelease?
    true
  end

  def reorder_versions
    rubygem.reorder_versions
  end

  def to_gem_version
    Gem::Version.new(number)
  end

  def info
    [ description, summary, "This rubygem does not have a description or summary." ].detect(&:present?)
  end

  def update_attributes_from_gem_specification!(spec)
    self.update_attributes!(
      :authors           => spec.authors.join(', '),
      :description       => spec.description,
      :summary           => spec.summary,
      :rubyforge_project => spec.rubyforge_project,
      :built_at          => spec.date,
      :indexed           => false
    )
  end

  def to_index
    [rubygem.name, to_gem_version, platform]
  end

  def <=>(other)
    self.to_gem_version <=> other.to_gem_version
  end

  def built_at_date
    built_at.to_date.to_formatted_s(:long)
  end

  def to_install
    command = "gem install #{rubygem.name}"
    command << " -v #{number}" if rubygem.versions.latest != self
    command
  end
end
