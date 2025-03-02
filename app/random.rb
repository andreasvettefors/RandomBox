#!/usr/bin/env ruby

# Show usage:
# % io.rb help

require 'json'
require 'open3'
require 'time'
require 'fileutils'
require 'pathname'
require 'rubygems'
require 'securerandom'

module Constants
  MINIMUM_RUBY_VERSION = "3.2.0"
  DEV_REPO_TAG_PREFIX = "android-iris-integrate-"
  GIT_HOST = "https://github.com"
  GIT_OWNER = "andreasvettefors"
  GIT_REPO_DEV = "RandomBox"
end

# Constants for paths and files
module Paths
  FILE_GHTOKEN = ".githubtoken.txt"

  FILE_SDK_RELEASE_AAR = "build/outputs/aar/app-release.aar"
  FILE_SDK_REPOSITORY_ZIP = "../../../.m2/repository/IRISintegrate.zip"

  PATH_SDK_REPOSITORY = "../../../.m2/repository"

  PATH_REPO_DEV = "#{Constants::GIT_OWNER}/#{Constants::GIT_REPO_DEV}"
  URL_REPO_DEV = "#{Constants::GIT_HOST}/#{PATH_REPO_DEV}"
end

# Helper class to handle version
class Version
  def initialize(version)
    @ver = Gem::Version.create(version)
  end

  def to_s
    "#{@ver}".sub(".pre.", "-")
  end
end

# Helper class to handle log printing
#
# Example of usage:
# Logger.info("Creating xcframwork")
#
# Change log level:
# Logger.set_loglevel(Loglevel::DEBUG)
module LogLevel
  DEBUG=1
  INFO=2
end

class Logger
  @@loglevel = LogLevel::DEBUG

  def self.debug(message)
    return if @@loglevel > LogLevel::DEBUG
    puts("[#{Time.now}] #{message}")
  end

  def self.info(message)
    return if @@loglevel > LogLevel::INFO
    puts("[#{Time.now}] #{message}")
  end

  def self.error(message)
    puts("ERROR: [#{Time.now}] #{message}")
  end

  def self.set_loglevel(loglevel)
    @@loglevel = loglevel
  end
end

# Helper class to run shell commands
#
# Example of running command in ./build folder and saving output to output.txt:
# Cmd.run(cmd: "ls -al", cd: "./build", log_file: "output.txt")
#
# Example of running command in current directory and returning output as an array:.
# success, output = Cmd.run(cmd: "ls -al")
#
# Arguments to run function
# cmd - Shell command
# cd - Work directory when executing the shell command. The current directory is used if nil is given.
# pipe_input - String to pass into command as standard input.
# env - Environment variables for the spawned process.
# log_file - Save output to file.
# log - Redirect stdout of spawned process stdout (default: true) (stderr is always redirected).
# err - Treat stderr of spawned process as error, if false redirect as stdout (default: true).
class Cmd
  def self.run(cmd: nil, cd: nil, pipe_input: nil, env: nil, log: true, err: true, log_file: nil)
    if log_file
      Logger.debug("  -> log_file: #{log_file}") if log
      File.delete(log_file) if File.exist?(log_file)
      FileUtils.mkdir_p(Pathname(log_file).dirname)
    end

    log_info = "> Running command: #{cmd}"
    log_info += " < #{pipe_input}" if pipe_input
    Logger.info(log_info) if log
    File.write(log_file, log_info, mode: "a") unless log_file.nil?

    cd = Dir.pwd() if cd.nil?
    env = {} if env.nil?

    output = []
    success = false
    command_elements = get_command_elements(cmd)
    begin
    Open3.popen3(env, *command_elements, :chdir=>cd) { |stdin, stdout, stderr, wt|
        if pipe_input
          stdin.write(pipe_input)
          stdin.close
        end
        stdout.each { |line|
          output.append(line)
          Logger.info("  -> #{line}") if log
          File.write(log_file, line, mode: "a") unless log_file.nil?
        }
        stderr.each { |line|
          output.append(line)
          if err
            Logger.error(line)
          else
            Logger.info(line) if log
          end
          File.write(log_file, line, mode: "a") unless log_file.nil?
        }
        success = wt.value.success?
      }
    rescue Exception => e
      Logger.error("Failed to run command: #{cmd}")
      Logger.error("> #{e}")
    end
    return success, output
  end

  private
  def self.get_command_elements(command)
    inside_quote = false
    command = command.chars.map { |character|
      result = character
      if character == "'"
        inside_quote = inside_quote ? false : true
        result = ''
      end
      if character == ' ' && inside_quote == false
        result = '€'
      end
      result
    }.join()
    return command.split("€")
  end
end


# Utility functions
module Util
  # Add auth token to URL string
  def self.add_token(url, token)
    url_components = url.split("://")
    unless url_components.length == 2
      raise Exception.new("add_token(url, token) called with invalid URL string: #{url}")
    end
    return "#{url_components.first}://#{token}@#{url_components[1]}"
  end

  # List tags in repository
  def self.list_git_tags(repo = "")
    success, output = Cmd.run(cmd: "git ls-remote --quiet --tags #{repo}", log: false)
    raise Exception.new("Failed to list tags for #{repo}") unless success
    return output.map { |line|
      line.split("/").last.strip
    }
  end
end


# Class that contains a library of steps we use in the subcommands
class Commands
  # Check github authentication status, if not authenticated try using FILE_GHTOKEN file
  def self.github_authenticate()
    gh_auth_status_check = -> {
      logged_in, output = Cmd.run(cmd: "gh auth status", log: false)
      unless logged_in
        return false, false
      end

      includes_scopes = false
      output.each do |line|
        if line.include?("Token scopes:")
          includes_scopes = ["read:org", "repo"].map { |scope| line.include?(scope) }.all? { |res| res == true }
        end
      end
      return true, includes_scopes
    }

    instructions_scopes = [
      "Authentication with github succeeded but with insufficient scopes. Please logout and re-authenticate.",
    ]
    instructions_no_token_file = [
      "Tried to automatically authenticate with github but file #{Paths::FILE_GHTOKEN} did not exist.",
    ]
    instructions_token_failed = [
      "Failed to authenticate with github using file #{Paths::FILE_GHTOKEN}.",
    ]
    instructions_token_failed_scopes = [
      "Authenticated with github using file #{Paths::FILE_GHTOKEN} but token granted insufficient scopes.",
    ]
    instructions_general = [
      "You need to be authenticated with github with the following scopes:",
      "> repo (all subscopes)",
      "> admin:org (subscope read:org)",
      "Authenticate using the GitHub CLI ('gh') or generate a token (https://github.com/settings/tokens) with sufficient scopes and store in file #{Paths::FILE_GHTOKEN} in the integrate module.",
    ]

    Logger.info("> Checking github auth status")
    (auth_status, auth_scopes) = gh_auth_status_check.call

    # Exit with error if we are authenticated with Github but with insufficient scopes
    if auth_status == true && auth_scopes == false
      (instructions_scopes + instructions_general).each { |line| Logger.error(line) }
      raise Exception.new("Aborting")
    end

    # Return if we are authenticated with Github with sufficient scopes
    if auth_status == true
      Logger.info("  -> Logged in to github")
      return
    end

    # If not try to authenticate with token file
    Logger.info("> Not authenticated. Trying to authenticate with github using #{Paths::FILE_GHTOKEN}")
    unless File.exist?(Paths::FILE_GHTOKEN)
      (instructions_no_token_file + instructions_general).each { |line| Logger.error(line) }
      raise Exception.new("Aborting")
    end

    Cmd.run(cmd: "gh auth login --with-token", pipe_input: File.read(Paths::FILE_GHTOKEN), log: false)
    (auth_status, auth_scopes) = gh_auth_status_check.call

    # Exit with error if we failed to authenticate
    unless auth_status == true
      (instructions_token_failed + instructions_general).each { |line| Logger.error(line) }
      raise Exception.new("Aborting")
    end

    # Exit with error if we authenticated with insufficient scopes
    unless auth_scopes == true
      (instructions_token_failed_scopes + instructions_general).each { |line| Logger.error(line) }
      raise Exception.new("Aborting")
    end
    Logger.info("  -> Logged in to github")
  end

  # Check if git working tree is clean
  def self.check_git_workspace_clean()
    _, output = Cmd.run(cmd: "git status --untracked-files=no --porcelain", log: false)
    unless output.length == 0
      Logger.error("The development repo contains uncommitted changes:")
      output.each { |line| Logger.error(line) }
      raise Exception.new("Aborting")
    end
  end

  # Clean build directory
  def self.clean()
      Logger.info("> Clean build directory")
      Cmd.run(cmd: "../gradlew clean")
  end

  # Run linter
  def self.lint()
    Logger.info("> Run IRISintegrate linter")
    Cmd.run(cmd: "../gradlew lint")
  end

  # Assemble sdk library
  def self.assemble_library()
    Logger.info("> Assemble sdk library")
    Cmd.run(cmd: "../gradlew assemble")
  end

  # Publish to maven local
  def self.publish_to_maven_local()
      Logger.info("> Publish to local maven")
      Cmd.run(cmd: "sudo ../gradlew -Dmaven.repo.local=/build publishToMavenLocal")
  end

  # Create zipped sdk repository
  def self.create_sdk_repository_zip()
      zip_file_path = Paths::FILE_SDK_REPOSITORY_ZIP
      Logger.info("> Create zip of IRISintegrate sdk repository")
      File.delete(zip_file_path) if File.exist?(zip_file_path)

      command = "zip -r IRISintegrate.zip se"
      success, _ = Cmd.run(cmd: command, cd: Paths::PATH_SDK_REPOSITORY )
      raise Exception.new("Failed to create IRISintegrate.zip") unless success
      return zip_file_path
  end

  def self.traverse_paths()
      publish_to_maven_local()
      command = "ls"
      success, _ = Cmd.run(cmd: command )
      pathe  ="../"
            success, _ = Cmd.run(cmd: command , cd: pathe)
      pathee  ="../../"
            success, _ = Cmd.run(cmd: command , cd: pathee)
      patheee  ="../../../"
      success, _ = Cmd.run(cmd: command , cd: patheee)
      patheeee  ="../../../../"
      success, _ = Cmd.run(cmd: command , cd: patheeee)
  end

  # Clone SDK repository to temp dir
  def self.clone_sdk_repo(sdk_repo_url)
    repo_name = sdk_repo_url.split("/").last

    success, token = Cmd.run(cmd: "gh auth token", log: false)
    raise Exception.new("Failed to retrieve github token") unless success
    token = token.first.strip

    _, output = Cmd.run(cmd: "mktemp -d -t sightic-XXX", log: false)
    temp_dir = output.first.strip
    repo_dir = "#{temp_dir}/#{repo_name}"

    Logger.info("> Cloning #{repo_name} to temporary directory")
    Logger.info("  -> #{repo_dir}")

    success, _ = Cmd.run(cmd: "git -C #{temp_dir} clone #{Util.add_token(sdk_repo_url, token)} -q", log: false)
    raise Exception.new("Failed to clone #{repo_name} to #{repo_dir}") unless success && Dir.exist?(repo_dir)
    return repo_dir
  end

  # Check if version to be published already exists
  def self.check_new_sdk_version(local_sdk_path, version)
    Logger.info("> Check if version exists in SDK repository")
    _, output = Cmd.run(cmd: "git -C #{local_sdk_path} tag --list", log: false)
    is_released = output.map { |tag| "#{Version.new(tag.delete_prefix('v.'))}" }.include? "#{version}"
    raise Exception.new("The version tag to be published already exists in SDK repository") if is_released
  end


  # Get current commit hash
  def self.get_commit_hash()
    _, output = Cmd.run(cmd: "git rev-parse --short HEAD", log: false)
    return output.first.strip.upcase
  end

  # Check if tag exists in repo
  # If repo is not specified, the repository at current working directory is used
  def self.check_tag_exists(tag, repo = nil)
    unless repo
      Logger.info("> Checking if tag #{tag} exists in current repository")
      tag_exists = Util.list_git_tags().include? "#{tag}"
    else
      Logger.info("> Checking if tag #{tag} exists in #{repo}")
      tag_exists = Util.list_git_tags(repo).include? "#{tag}"
    end
    return tag_exists
  end

  # Get current SDK version from gradle task
  def self.get_library_version()
    version_string = nil
    success, output = Cmd.run(cmd: "../gradlew getLibraryVersion --no-configuration-cache")
    raise Exception.new("Couldn't get library version from build.gradle") unless success
    Logger.info("#{output} retrieved from build.gradle")
    # Find the version string in output array
    version_string = output.find {|o| /^([1-9]\d*|0)(\.(([1-9]\d*)|0)){2}$/ =~ o }
    Logger.info("#{version_string} retrieved from build.gradle")
    raise Exception.new("Missing <ver> argument") if version_string.nil?
    return Version.new(version_string)
  end

  # Verify SDK version string in LibraryVersion.kt
  def self.verify_library_version(version)
    Logger.info("> Verifying LibraryVersion.kt")
    version_string = "#{version}"
    Logger.info("  -> Expected version string: #{version_string}")

    version_string_ok = false
    version_string_found = "none"
    File.readlines(Paths::FILE_LIBRARYVERSION).each { |line|
      if line.include? "var version = "
        res = line.split('"')
        version_string_found = res[1] if res.length > 1
        version_string_ok = version_string_found == version_string
      end
    }

    unless version_string_ok
      Logger.error("Version string in LibraryVersion.kt does not match tag")
      Logger.error("Expected '#{version_string}', found '#{version_string_found}'")
      raise Exception.new("Aborting")
    end
    Logger.info("  -> LibraryVersion.kt contains the expected version string")
  end

  # Tag release in development repo
  def self.tag_release(tag, version, commit_id)
    Logger.info("> Tag release in development repo: #{version} / #{tag}")
    Cmd.run(cmd: "git tag -a #{tag} -m 'Android SDK release #{version}' #{commit_id}", err: false)
    Cmd.run(cmd: "git push origin #{tag}", err: false)
  end

  # Create new release in repository
  def self.create_new_sdk_release(local_sdk_path, sdk_repo_url, version, files)
    repo_name = sdk_repo_url.split("/").last
    Logger.info("> Create sdk release #{version} on #{repo_name}")

    env = {"GIT_COMMITTER_NAME"=>"Sightic", "GIT_COMMITTER_EMAIL"=>"noreply@sightic.com"}
    Cmd.run(cmd: "git -C #{local_sdk_path} tag -a #{version} -m 'IRIS integrate release #{version}'", env: env, err: false)
    Cmd.run(cmd: "git -C #{local_sdk_path} push origin #{version}", err: false)

    files_concatenated = files.map { |f| "'#{f}'" }.join(" ")

    command = "gh release create #{version} #{files_concatenated} " \
              "--repo #{sdk_repo_url} " \
              "--title #{version}"
    Cmd.run(cmd: command)
  end
end

# Class containing methods for each subcommand the script supports
class Subcommands
  def self.help()
    puts("Usage: io.rb <command>")
    puts("")
    puts("Commands:")
    puts("  publish         Build and publish repository release to iris-integrate-android-dev")
    puts()
    puts("  build           Build sdk library zip")
    puts("  assemble        Assemble library aar")
    puts("  clean           Clean up intermediate build files")
    puts()
    puts("  help            Show this help")
    puts()
    puts("Examples:")
    puts("  # ruby io.rb publish")
    puts("    Build and publish repository to iris-integrate-android-dev repo")
  end

  def self.assemble()
     Commands.assemble_library()
  end

  def self.build()
      Commands.publish_to_maven_local()
      return Commands.create_sdk_repository_zip()
  end

  def self.something()
      Commands.traverse_paths()
  end

  def self.clean()
      Commands.clean()
  end

  def self.publish()
    version = Version.new("#{Commands.get_library_version()}-git#{Commands.get_commit_hash()}")
    Logger.info("Build and publish sdk #{version} to DEV")

    Commands.github_authenticate()
    Commands.check_git_workspace_clean()

    sdk_repo_url = Paths::URL_REPO_DEV

    # Created zipped sdk repository
    sdk_zip_path = build()

    # Clone and verify dev release repository
    sdk_path = Commands.clone_sdk_repo(sdk_repo_url)
    Commands.check_new_sdk_version(sdk_path, version)

    Commands.create_new_sdk_release(sdk_path, sdk_repo_url, version, [sdk_zip_path])
  end
end

def io(argv)
  case cmd = argv.shift
  when "publish"
    Subcommands.publish()
  when "build"
    Subcommands.build()
  when "assemble"
    Subcommands.assemble()
  when "something"
    Subcommands.something()
  when "clean"
    Subcommands.clean()
  when "help"
    Subcommands.help()
  else
    unless cmd.nil?
      print("Unrecognized command: #{cmd}\n\n")
    end
    Subcommands.help()
  end
end

def check_prerequisites()
  # Check current ruby version
  if Gem::Version.new(RUBY_VERSION) < Gem::Version.new(Constants::MINIMUM_RUBY_VERSION)
    Logger.error("> Current ruby version too old (#{RUBY_VERSION}, required version >= #{Constants::MINIMUM_RUBY_VERSION})")
    Logger.error("  -> Use rbenv to install the version specified in .ruby_version:")
    Logger.error("  -> % rbenv install")
    Logger.error("  -> https://github.com/rbenv/rbenv")
    exit(1)
  end

  # Check if `gh` command is installed
  result, _ = Cmd.run(cmd: "which gh", log: false)
  unless result
    Logger.error("Please install GitHub CLI using 'brew install gh' according to https://github.com/cli/cli#installation.")
    exit(1)
  end
end

begin
  Logger.set_loglevel(LogLevel::INFO)
  check_prerequisites()
  io(ARGV)
rescue Exception => e
  Logger.error("#{e}")
  exit(1)
end
