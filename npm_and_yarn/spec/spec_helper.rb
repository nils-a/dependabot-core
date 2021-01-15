# frozen_string_literal: true

def common_dir
  @common_dir ||= Gem::Specification.find_by_name("dependabot-common").gem_dir
end

def require_common_spec(path)
  require "#{common_dir}/spec/dependabot/#{path}"
end

require "#{common_dir}/spec/spec_helper.rb"

class ProjectFixtureBuilder
  class << self
    attr_accessor :storage, :current_group
  end

  self.storage = {}

  MANIFEST_FIXTURE_LETS = %i(
    manifest_fixture_name
  ).freeze

  LOCKFILE_FIXTURE_LETS = %i(
    npm_lockfile_fixture_name
    npm_lock_fixture_name
    npm_shrinkwrap_fixture_name
    yarn_lock_fixture_name
    yarn_lockfile_fixture_name
  ).freeze

  FIXTURE_NAMES = MANIFEST_FIXTURE_LETS | LOCKFILE_FIXTURE_LETS
  FILE_NAMES = %i(files dependency_files)

  def self.example_group
    RSpec::Core::ExampleGroup
  end

  def example_group.let(name, &block)
    super(name, &block)

    ProjectFixtureBuilder.prepend_behavior(self, name) do |metadata, evaluated_block|
      # puts name
      # puts caller_locations(1..1).first
      # puts block.source_location

      key = ExampleGroupData.key(metadata)
      data = ProjectFixtureBuilder.storage.fetch(key) { ExampleGroupData.new(metadata) }
      if FILE_NAMES.include?(name.to_sym)
        # In this case, the block will return an array of files
        files = evaluated_block

        files.each do |file|
          data.add_file(file) if file.is_a?(Dependabot::DependencyFile)
        end
      elsif FIXTURE_NAMES.include?(name.to_sym)
        # In this case, the block will return an array of fixture names
        data.add_fixture_name(evaluated_block)
      end
      ProjectFixtureBuilder.current_group = data
      ProjectFixtureBuilder.storage[key] = data
    end
  end

  def self.prepend_behavior(scope, method_name)
    original_method = scope.instance_method(method_name)

    scope.__send__(:define_method, method_name) do |*args, &block|
      evaluated_block = original_method.bind(self).call(*args, &block)
      yield self.class.metadata, evaluated_block

      original_method.bind(self).call(*args, &block)
    end
  end

  class ExampleGroupData
    attr_reader :metadata, :files, :fixture_names

    def initialize(metadata)
      @metadata = metadata
      @files = Set[]
      @fixture_names = Set[]
    end

    def self.key(metadata)
      Digest::SHA256.hexdigest(metadata[:full_description])
    end

    def add_fixture_name(name)
      @fixture_names << name
    end

    def add_file(file)
      @files << file
    end

    def project_name
      @fixture_names.to_a.map { |f| File.basename(f, File.extname(f)) }.join("_")
    end
  end
end

class ProjectBuilder
  attr_reader :data

  BASE_FOLDER = "npm_and_yarn/spec/fixtures/projects/"

  def initialize(data)
    @data = data
  end

  def run
    project_dir = FileUtils.mkdir_p(File.join(BASE_FOLDER, subfolder, data.project_name)).last
    Dir.chdir(project_dir) do
      data.files.each do |file|
        if file.directory == "/"
          File.write(file.name, file.content)
        else
          subdir = FileUtils.mkdir(file.directory).last
          Dir.chdir(subdir) { File.write(file.name, file.content) }
        end
      end
    end

    project_dir
  end

  def subfolder
    if yarn_lock? && package_lock?
      "generic"
    elsif yarn_lock?
      "yarn"
    elsif package_lock?
      "npm6"
    else
      "generic"
    end
  end

  def yarn_lock?
    data.files.map(&:name).include?("yarn.lock")
  end

  def package_lock?
    data.files.map(&:name).include?("package-lock.json")
  end
end

RSpec.configure do |c|
  c.after do
    ProjectFixtureBuilder.storage.each do |_, data|
      dir = ProjectBuilder.new(data).run

      puts "Created fixtures for `#{data.metadata[:full_description]}` (#{data.metadata[:location]}) in #{dir}"
      puts "Add `let(:project_name) { \"#{data.project_name}\" }` to that example group"
    end
  end
end
