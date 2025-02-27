# frozen_string_literal: true

require "shellwords"
require "utils"

class UsageError < RuntimeError
  attr_reader :reason

  def initialize(reason = nil)
    @reason = reason
  end

  def to_s
    s = "Invalid usage"
    s += ": #{reason}" if reason
    s
  end
end

class FormulaUnspecifiedError < UsageError
  def initialize
    super "this command requires a formula argument"
  end
end

class KegUnspecifiedError < UsageError
  def initialize
    super "this command requires a keg argument"
  end
end

class MultipleVersionsInstalledError < RuntimeError; end

class NotAKegError < RuntimeError; end

class NoSuchKegError < RuntimeError
  attr_reader :name

  def initialize(name)
    @name = name
    super "No such keg: #{HOMEBREW_CELLAR}/#{name}"
  end
end

class FormulaValidationError < StandardError
  attr_reader :attr, :formula

  def initialize(formula, attr, value)
    @attr = attr
    @formula = formula
    super "invalid attribute for formula '#{formula}': #{attr} (#{value.inspect})"
  end
end

class FormulaSpecificationError < StandardError; end

class MethodDeprecatedError < StandardError
  attr_accessor :issues_url
end

class FormulaUnavailableError < RuntimeError
  attr_reader :name
  attr_accessor :dependent

  def initialize(name)
    @name = name
  end

  def dependent_s
    "(dependency of #{dependent})" if dependent && dependent != name
  end

  def to_s
    "No available formula with the name \"#{name}\" #{dependent_s}"
  end
end

module FormulaClassUnavailableErrorModule
  attr_reader :path, :class_name, :class_list

  def to_s
    s = super
    s += "\nIn formula file: #{path}"
    s += "\nExpected to find class #{class_name}, but #{class_list_s}."
    s
  end

  private

  def class_list_s
    formula_class_list = class_list.select { |klass| klass < Formula }
    if class_list.empty?
      "found no classes"
    elsif formula_class_list.empty?
      "only found: #{format_list(class_list)} (not derived from Formula!)"
    else
      "only found: #{format_list(formula_class_list)}"
    end
  end

  def format_list(class_list)
    class_list.map { |klass| klass.name.split("::").last }.join(", ")
  end
end

class FormulaClassUnavailableError < FormulaUnavailableError
  include FormulaClassUnavailableErrorModule

  def initialize(name, path, class_name, class_list)
    @path = path
    @class_name = class_name
    @class_list = class_list
    super name
  end
end

module FormulaUnreadableErrorModule
  attr_reader :formula_error

  def to_s
    "#{name}: " + formula_error.to_s
  end
end

class FormulaUnreadableError < FormulaUnavailableError
  include FormulaUnreadableErrorModule

  def initialize(name, error)
    super(name)
    @formula_error = error
  end
end

class TapFormulaUnavailableError < FormulaUnavailableError
  attr_reader :tap, :user, :repo

  def initialize(tap, name)
    @tap = tap
    @user = tap.user
    @repo = tap.repo
    super "#{tap}/#{name}"
  end

  def to_s
    s = super
    s += "\nPlease tap it and then try again: brew tap #{tap}" unless tap.installed?
    s
  end
end

class TapFormulaClassUnavailableError < TapFormulaUnavailableError
  include FormulaClassUnavailableErrorModule

  attr_reader :tap

  def initialize(tap, name, path, class_name, class_list)
    @path = path
    @class_name = class_name
    @class_list = class_list
    super tap, name
  end
end

class TapFormulaUnreadableError < TapFormulaUnavailableError
  include FormulaUnreadableErrorModule

  def initialize(tap, name, error)
    super(tap, name)
    @formula_error = error
  end
end

class TapFormulaAmbiguityError < RuntimeError
  attr_reader :name, :paths, :formulae

  def initialize(name, paths)
    @name = name
    @paths = paths
    @formulae = paths.map do |path|
      "#{Tap.from_path(path).name}/#{path.basename(".rb")}"
    end

    super <<~EOS
      Formulae found in multiple taps: #{formulae.map { |f| "\n       * #{f}" }.join}

      Please use the fully-qualified name (e.g. #{formulae.first}) to refer to the formula.
    EOS
  end
end

class TapFormulaWithOldnameAmbiguityError < RuntimeError
  attr_reader :name, :possible_tap_newname_formulae, :taps

  def initialize(name, possible_tap_newname_formulae)
    @name = name
    @possible_tap_newname_formulae = possible_tap_newname_formulae

    @taps = possible_tap_newname_formulae.map do |newname|
      newname =~ HOMEBREW_TAP_FORMULA_REGEX
      "#{Regexp.last_match(1)}/#{Regexp.last_match(2)}"
    end

    super <<~EOS
      Formulae with '#{name}' old name found in multiple taps: #{taps.map { |t| "\n       * #{t}" }.join}

      Please use the fully-qualified name (e.g. #{taps.first}/#{name}) to refer to the formula or use its new name.
    EOS
  end
end

class TapUnavailableError < RuntimeError
  attr_reader :name

  def initialize(name)
    @name = name

    super <<~EOS
      No available tap #{name}.
    EOS
  end
end

class TapRemoteMismatchError < RuntimeError
  attr_reader :name, :expected_remote, :actual_remote

  def initialize(name, expected_remote, actual_remote)
    @name = name
    @expected_remote = expected_remote
    @actual_remote = actual_remote

    super <<~EOS
      Tap #{name} remote mismatch.
      #{expected_remote} != #{actual_remote}
    EOS
  end
end

class TapAlreadyTappedError < RuntimeError
  attr_reader :name

  def initialize(name)
    @name = name

    super <<~EOS
      Tap #{name} already tapped.
    EOS
  end
end

class TapPinStatusError < RuntimeError
  attr_reader :name, :pinned

  def initialize(name, pinned)
    @name = name
    @pinned = pinned

    super pinned ? "#{name} is already pinned." : "#{name} is already unpinned."
  end
end

class OperationInProgressError < RuntimeError
  def initialize(name)
    message = <<~EOS
      Operation already in progress for #{name}
      Another active Homebrew process is already using #{name}.
      Please wait for it to finish or terminate it to continue.
    EOS

    super message
  end
end

class CannotInstallFormulaError < RuntimeError; end

class FormulaInstallationAlreadyAttemptedError < RuntimeError
  def initialize(formula)
    super "Formula installation already attempted: #{formula.full_name}"
  end
end

class UnsatisfiedRequirements < RuntimeError
  def initialize(reqs)
    if reqs.length == 1
      super "An unsatisfied requirement failed this build."
    else
      super "Unsatisfied requirements failed this build."
    end
  end
end

class FormulaConflictError < RuntimeError
  attr_reader :formula, :conflicts

  def initialize(formula, conflicts)
    @formula = formula
    @conflicts = conflicts
    super message
  end

  def conflict_message(conflict)
    message = []
    message << "  #{conflict.name}"
    message << ": because #{conflict.reason}" if conflict.reason
    message.join
  end

  def message
    message = []
    message << "Cannot install #{formula.full_name} because conflicting formulae are installed."
    message.concat conflicts.map { |c| conflict_message(c) } << ""
    message << <<~EOS
      Please `brew unlink #{conflicts.map(&:name) * " "}` before continuing.

      Unlinking removes a formula's symlinks from #{HOMEBREW_PREFIX}. You can
      link the formula again after the install finishes. You can --force this
      install, but the build may fail or cause obscure side effects in the
      resulting software.
    EOS
    message.join("\n")
  end
end

class FormulaUnknownPythonError < RuntimeError
  def initialize(formula)
    super <<~EOS
      The version of Python to use with the virtualenv in the `#{formula.full_name}` formula
      cannot be guessed automatically because a recognised Python dependency could not be found.

      If you are using a non-standard Python depedency, please add `:using => "python@x.y"` to
      `virtualenv_install_with_resources` to resolve the issue manually.
    EOS
  end
end

class FormulaAmbiguousPythonError < RuntimeError
  def initialize(formula)
    super <<~EOS
      The version of python to use with the virtualenv in the `#{formula.full_name}` formula
      cannot be guessed automatically. If the simultaneous use of multiple pythons
      is intentional, please add `:using => "python@x.y"` to
      `virtualenv_install_with_resources` to resolve the ambiguity manually.
    EOS
  end
end

class BuildError < RuntimeError
  attr_reader :cmd, :args, :env
  attr_accessor :formula, :options

  def initialize(formula, cmd, args, env)
    @formula = formula
    @cmd = cmd
    @args = args
    @env = env
    pretty_args = Array(args).map { |arg| arg.to_s.gsub " ", "\\ " }.join(" ")
    super "Failed executing: #{cmd} #{pretty_args}".strip
  end

  def issues
    @issues ||= fetch_issues
  end

  def fetch_issues
    GitHub.issues_for_formula(formula.name, tap: formula.tap, state: "open")
  rescue GitHub::RateLimitExceededError => e
    opoo e.message
    []
  end

  def dump
    puts

    if Homebrew.args.verbose?
      require "system_config"
      require "build_environment"

      ohai "Formula"
      puts "Tap: #{formula.tap}" if formula.tap?
      puts "Path: #{formula.path}"
      ohai "Configuration"
      SystemConfig.dump_verbose_config
      ohai "ENV"
      Homebrew.dump_build_env(env)
      puts
      onoe "#{formula.full_name} #{formula.version} did not build"
      unless (logs = Dir["#{formula.logs}/*"]).empty?
        puts "Logs:"
        puts logs.map { |fn| "     #{fn}" }.join("\n")
      end
    end

    if formula.tap && defined?(OS::ISSUES_URL)
      if formula.tap.official?
        puts Formatter.error(Formatter.url(OS::ISSUES_URL), label: "READ THIS")
      elsif issues_url = formula.tap.issues_url
        puts <<~EOS
          If reporting this issue please do so at (not Homebrew/brew or Homebrew/core):
            #{Formatter.url(issues_url)}
        EOS
      else
        puts <<~EOS
          If reporting this issue please do so to (not Homebrew/brew or Homebrew/core):
            #{formula.tap}
        EOS
      end
    else
      puts <<~EOS
        Do not report this issue to Homebrew/brew or Homebrew/core!
      EOS
    end

    puts

    if issues.present?
      puts "These open issues may also help:"
      puts issues.map { |i| "#{i["title"]} #{i["html_url"]}" }.join("\n")
    end

    require "diagnostic"
    checks = Homebrew::Diagnostic::Checks.new
    checks.build_error_checks.each do |check|
      out = checks.send(check)
      next if out.nil?

      puts
      ofail out
    end
  end
end

# Raised by {FormulaInstaller#check_dependencies_bottled} and
# {FormulaInstaller#install} if the formula or its dependencies are not bottled
# and are being installed on a system without necessary build tools.
class BuildToolsError < RuntimeError
  def initialize(formulae)
    super <<~EOS
      The following #{"formula".pluralize(formulae.count)}
        #{formulae.to_sentence}
      cannot be installed as #{"binary package".pluralize(formulae.count)} and must be built from source.
      #{DevelopmentTools.installation_instructions}
    EOS
  end
end

# Raised by Homebrew.install, Homebrew.reinstall, and Homebrew.upgrade
# if the user passes any flags/environment that would case a bottle-only
# installation on a system without build tools to fail.
class BuildFlagsError < RuntimeError
  def initialize(flags, bottled: true)
    if flags.length > 1
      flag_text = "flags"
      require_text = "require"
    else
      flag_text = "flag"
      require_text = "requires"
    end

    bottle_text = if bottled
      <<~EOS
        Alternatively, remove the #{flag_text} to attempt bottle installation.
      EOS
    end

    message = <<~EOS
      The following #{flag_text}:
        #{flags.join(", ")}
      #{require_text} building tools, but none are installed.
      #{DevelopmentTools.installation_instructions}#{bottle_text}
    EOS

    super message
  end
end

# Raised by {CompilerSelector} if the formula fails with all of
# the compilers available on the user's system.
class CompilerSelectionError < RuntimeError
  def initialize(formula)
    super <<~EOS
      #{formula.full_name} cannot be built with any available compilers.
      #{DevelopmentTools.custom_installation_instructions}
    EOS
  end
end

# Raised in {Resource#fetch}.
class DownloadError < RuntimeError
  def initialize(resource, cause)
    super <<~EOS
      Failed to download resource #{resource.download_name.inspect}
      #{cause.message}
    EOS
    set_backtrace(cause.backtrace)
  end
end

# Raised in {CurlDownloadStrategy#fetch}.
class CurlDownloadStrategyError < RuntimeError
  def initialize(url)
    case url
    when %r{^file://(.+)}
      super "File does not exist: #{Regexp.last_match(1)}"
    else
      super "Download failed: #{url}"
    end
  end
end

# Raised by {#safe_system} in `utils.rb`.
class ErrorDuringExecution < RuntimeError
  attr_reader :cmd, :status, :output

  def initialize(cmd, status:, output: nil, secrets: [])
    @cmd = cmd
    @status = status
    @output = output

    exitstatus = if status.respond_to?(:exitstatus)
      status.exitstatus
    else
      status
    end

    redacted_cmd = redact_secrets(cmd.shelljoin.gsub('\=', "="), secrets)
    s = +"Failure while executing; `#{redacted_cmd}` exited with #{exitstatus}."

    if Array(output).present?
      format_output_line = lambda do |type_line|
        type, line = *type_line
        if type == :stderr
          Formatter.error(line)
        else
          line
        end
      end

      s << " Here's the output:\n"
      s << output.map(&format_output_line).join
      s << "\n" unless s.end_with?("\n")
    end

    super s.freeze
  end

  def stderr
    Array(output).select { |type,| type == :stderr }.map(&:last).join
  end
end

# Raised by {Pathname#verify_checksum} when "expected" is nil or empty.
class ChecksumMissingError < ArgumentError; end

# Raised by {Pathname#verify_checksum} when verification fails.
class ChecksumMismatchError < RuntimeError
  attr_reader :expected, :hash_type

  def initialize(fn, expected, actual)
    @expected = expected
    @hash_type = expected.hash_type.to_s.upcase

    super <<~EOS
      #{@hash_type} mismatch
      Expected: #{expected}
        Actual: #{actual}
       Archive: #{fn}
      To retry an incomplete download, remove the file above.
    EOS
  end
end

class ResourceMissingError < ArgumentError
  def initialize(formula, resource)
    super "#{formula.full_name} does not define resource #{resource.inspect}"
  end
end

class DuplicateResourceError < ArgumentError
  def initialize(resource)
    super "Resource #{resource.inspect} is defined more than once"
  end
end

# Raised when a single patch file is not found and apply hasn't been specified.
class MissingApplyError < RuntimeError; end

class BottleFormulaUnavailableError < RuntimeError
  def initialize(bottle_path, formula_path)
    super <<~EOS
      This bottle does not contain the formula file:
        #{bottle_path}
        #{formula_path}
    EOS
  end
end

# Raised when a child process sends us an exception over its error pipe.
class ChildProcessError < RuntimeError
  attr_reader :inner, :inner_class

  def initialize(inner)
    @inner = inner
    @inner_class = Object.const_get inner["json_class"]

    super <<~EOS
      An exception occurred within a child process:
        #{inner_class}: #{inner["m"]}
    EOS

    # Clobber our real (but irrelevant) backtrace with that of the inner exception.
    set_backtrace inner["b"]
  end
end

class MacOSVersionError < RuntimeError
  attr_reader :version

  def initialize(version)
    @version = version
    super "unknown or unsupported macOS version: #{version.inspect}"
  end
end
