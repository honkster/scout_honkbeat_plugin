require "rubygems"
require "spec"
require "spec/autorun"
require "rr"
require "fileutils"
require "logger"


module Scout
  class Plugin
    attr_reader :alerts, :report_attr, :logger

    def initialize
      @alerts = []
      @report_attr = nil
      @logger = Logger.new(StringIO.new(""))
    end

    def alert(a)
      @alerts << a
    end

    def report(hash)
      @report_attr = hash
    end
  end
end

require File.dirname(__FILE__) + "/../lib/scout_honkbeat_plugin"
require File.dirname(__FILE__) + "/../lib/scout_external_dependency_plugin"

Spec::Runner.configure do |config|
  config.mock_with RR::Adapters::Rspec
end

class Spec::ExampleGroup
  def self.it_with_definition_backtrace(*args, &block)
    definition_backtrace = caller.join("\n\t")
    it(*args) do
      begin
        instance_eval(&block)
      rescue => e
        e.message.replace("#{e.message}\n#{ definition_backtrace }")
        raise e
      end
    end
  end

  def match_in_collection(matcher)
    if matcher.is_a?(Regexp)
      simple_matcher(%Q|match #{matcher.inspect} in the collection|) do |given|
        given.any? {|i| i =~ matcher}
      end
    else
      simple_matcher(%Q|match '#{matcher}' in the collection|) do |given|
        given.any? {|i| i == matcher}
      end
    end
  end
end