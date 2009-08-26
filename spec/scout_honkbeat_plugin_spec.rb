require "#{File.dirname(__FILE__)}/spec_helper"

describe ScoutHonkbeatPlugin do
  attr_reader :plugin, :shared_dir, :machine_status_file_path

  before do
    @plugin = ScoutHonkbeatPlugin.new
    @shared_dir = "#{File.dirname(__FILE__)}/shared_dir"
    FileUtils.rm_rf(shared_dir)
    FileUtils.mkdir_p(shared_dir)
    stub(@plugin).status_path { shared_dir }

    @machine_status_file_path = "#{shared_dir}/machine_status.txt"

    stub(plugin).memory { nil }
    stub(plugin).remember
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

  describe "#build_report" do
    def self.should_periodically_send_error_alerts (memory_item_name, error_message)
      context "when memory(#{memory_item_name.inspect}) is nil" do
        before do
          mock(plugin).memory(memory_item_name) {nil}
        end

        it_with_definition_backtrace "sends an alert about the error" do
          plugin.build_report
          plugin.alerts.should match_in_collection(error_message)
        end

        it_with_definition_backtrace "remembers the current Time" do
          now = Time.now
          stub(Time).now {now}
          mock(plugin).remember(memory_item_name, now)

          plugin.build_report
        end
      end

      context "when memory(#{memory_item_name.inspect}) is within the last ScoutHonkbeatPlugin::ALERT_INTERVAL_IN_MINUTES minutes" do
        attr_reader :last_alert_sent_at
        before do
          @last_alert_sent_at = Time.now - ((ScoutHonkbeatPlugin::ALERT_INTERVAL_IN_MINUTES - 1) * 60)
          mock(plugin).memory(memory_item_name) { last_alert_sent_at }
        end

        it_with_definition_backtrace "does not send an alert about the error" do
          plugin.build_report
          plugin.alerts.should_not match_in_collection(error_message)
        end

        it_with_definition_backtrace "remembers the existing memory_item_name" do
          mock(plugin).remember(memory_item_name, last_alert_sent_at)
          plugin.build_report
        end
      end

      context "when memory(#{memory_item_name.inspect}) is more than ScoutHonkbeatPlugin::ALERT_INTERVAL_IN_MINUTES minutes ago" do
        attr_reader :last_alert_sent_at
        before do
          @last_alert_sent_at = Time.now - ((ScoutHonkbeatPlugin::ALERT_INTERVAL_IN_MINUTES + 1) * 60)
          mock(plugin).memory(memory_item_name) { last_alert_sent_at }
        end

        it_with_definition_backtrace "sends an alert about the missing machine status file" do
          plugin.build_report
          plugin.alerts.should match_in_collection(error_message)
        end

        it_with_definition_backtrace "remembers the current Time" do
          now = Time.now
          stub(Time).now {now}
          mock(plugin).remember(memory_item_name, now)

          plugin.build_report
        end
      end
    end

    def self.should_send_success_alert(memory_item_name, success_message)
      context "when #{memory_item_name.inspect} is not present" do
        before do
          mock(plugin).memory(memory_item_name) {nil}
        end

        it_with_definition_backtrace "should not remember #{memory_item_name.inspect}" do
          dont_allow(plugin).remember(memory_item_name, anything)
          plugin.build_report
        end

        it_with_definition_backtrace "should not send an alert indicating that the machine status file is back" do
          plugin.build_report
          plugin.alerts.should_not match_in_collection(success_message)
        end
      end

      context "when #{memory_item_name.inspect} is present" do
        before do
          mock(plugin).memory(memory_item_name) {Time.now}
        end

        it_with_definition_backtrace "should not remember #{memory_item_name.inspect}" do
          dont_allow(plugin).remember(memory_item_name, anything)
          plugin.build_report
        end

        it_with_definition_backtrace "should send an alert indicating that the machine status file is back" do
          plugin.build_report
          plugin.alerts.should match_in_collection(success_message)
        end
      end
    end

    context "when the machine status file does not exist" do
      before do
        File.exists?(machine_status_file_path).should be_false
      end

      should_periodically_send_error_alerts(:last_missing_file_alert_sent_at, /Error: machine_status.txt is missing/)
    end

    context "when the machine status file exists" do
      before do
        File.open(machine_status_file_path, "w") do |file|
          file.write([].to_json)
        end
        File.exists?(machine_status_file_path).should be_true
      end

      describe "freshness of machine status file" do
        it "should not alert about a missing machine status file" do
          plugin.build_report
          plugin.alerts.should_not match_in_collection("Error: machine_status.txt is missing")
        end

        should_send_success_alert(:last_missing_file_alert_sent_at, "Success: machine_status.txt is back")

        context "when the machine status file is less than ScoutHonkbeatPlugin::STALE_FILE_THRESHOLD_IN_MINUTES minutes old" do
          before do
            File.mtime(machine_status_file_path).should > (Time.now - (ScoutHonkbeatPlugin::STALE_FILE_THRESHOLD_IN_MINUTES - 1) * 60)
          end

          context "when :last_stale_file_alert_sent_at is not set" do
            it "should not alert about the age of the machine status file" do
              plugin.build_report
              plugin.alerts.should_not match_in_collection("Error: machine_status.txt is stale")
            end

            it "should not remember :last_stale_file_alert_sent_at" do
              dont_allow(plugin).remember(:last_stale_file_alert_sent_at, anything)
              plugin.build_report
            end
          end

          should_send_success_alert(:last_stale_file_alert_sent_at, "Success: machine_status.txt is no longer stale")
        end

        context "when the machine status file is more than ScoutHonkbeatPlugin::STALE_FILE_THRESHOLD_IN_MINUTES minutes old" do
          before do
            time = Time.now - ((ScoutHonkbeatPlugin::STALE_FILE_THRESHOLD_IN_MINUTES + 1) * 60)
            system "touch -t #{time.strftime('%Y%m%d%H%M.%S')} #{machine_status_file_path}"
            File.exists?(machine_status_file_path).should be_true
          end

          should_periodically_send_error_alerts(:last_stale_file_alert_sent_at, "Error: machine_status.txt is stale")
        end
      end

      describe "contents of machine status file" do
        context "there are errors on mongrels on this machine" do
          before do
            File.open(machine_status_file_path, 'w') do |file|
              file.print [{
                'hostname' => 'hostname1',
                'port' => 5000,
                'checks' => {
                  'database' => "Cannot connect to database",
                  'memcached' => "Cannot connect to memcached",
                  }
              }, {
                'hostname' => 'hostname1',
                'port' => 5001,
                'checks' => {
                  'solr' => "Cannot connect to solr",
                  }
              }].to_json
            end
          end

          context "when the same errors have been seen previously" do
            before do
              set_memory(:down, ["- database on hostname1:5000", "- memcached on hostname1:5000", "- solr on hostname1:5001"])
            end

            should_periodically_send_error_alerts(
              :last_machine_error_alert_sent_at,
              "Error: The following services are DOWN:\n- database on hostname1:5000\n- memcached on hostname1:5000\n- solr on hostname1:5001"
            )
          end

          context "when the same errors have not been seen previously" do
            it "sends an alert about the errors" do
              plugin.build_report
              plugin.alerts.should include("Error: The following services are DOWN:\n- database on hostname1:5000\n- memcached on hostname1:5000\n- solr on hostname1:5001")
            end
          end

          context "there are some errors on this machine that are now gone" do
            before do
              set_memory(:down, ["- database on hostname1:5000", "- database on hostname1:5002", "- memcached on hostname1:5000", "- solr on hostname1:5001"])
            end

            it "should alert us that the database on hostname1:5002 has come back up" do
              plugin.build_report
              plugin.alerts.should include("Success: The following services are UP:\n- database on hostname1:5002")
            end

            it "should alert us about the systems that are still down" do
              plugin.build_report
              plugin.alerts.should include("Error: The following services are DOWN:\n- database on hostname1:5000\n- memcached on hostname1:5000\n- solr on hostname1:5001")
            end
          end

          context "there are additional services down now that were not down before" do
            before do
              set_memory(:down, ["- memcached on hostname1:5000", "- solr on hostname1:5001"])
            end

            it "should not send a success message" do
              plugin.build_report
              plugin.alerts.should_not include(/Success/)
            end

            it "should send a down alert message" do
              plugin.build_report
              plugin.alerts.should include("Error: The following services are DOWN:\n- database on hostname1:5000\n- memcached on hostname1:5000\n- solr on hostname1:5001")
            end
          end

        end

        context "there are no mongrel errors now, and were some before" do
          before do
            set_memory(:down, ["- database on hostname1:5002"])
          end

          it "should send a success alert" do
            plugin.build_report
            plugin.alerts.should include("Success: The following services are UP:\n- database on hostname1:5002")
          end
        end

        context "there are no mongrel errors now, and were none before" do
          it "should send no alerts" do
            plugin.build_report
            plugin.alerts.should be_empty
          end
        end
      end
    end

    def set_memory(key, value)
      mock(plugin).memory(key) {value}
    end
  end
end