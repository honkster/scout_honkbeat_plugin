require "#{File.dirname(__FILE__)}/spec_helper"

describe ScoutHonkbeatPlugin do
  attr_reader :plugin, :shared_dir, :machine_status_path, :dependency_status_path

  before do
    @plugin = ScoutHonkbeatPlugin.new
    @shared_dir = "#{File.dirname(__FILE__)}/shared_dir"
    FileUtils.rm_rf(shared_dir)
    FileUtils.mkdir_p(shared_dir)
    stub(@plugin).status_path { shared_dir }

    @machine_status_path = "#{shared_dir}/machine_status.txt"
    @dependency_status_path = "#{shared_dir}/dependency_status.txt"

    stub(plugin).memory { nil }
    stub(plugin).remember
  end

  describe "#build_report" do
    describe "mongrels" do

      context "when the machine status file does not exist" do
        def self.should_alert_and_remember_current_time
          it "sends an alert about the missing machine status file" do
            plugin.build_report
            plugin.alerts.should include("Error: machine_status.txt is missing")
          end

          it "remembers the current Time" do
            now = Time.now
            stub(Time).now {now}
            mock(plugin).remember(:last_missing_file_alert_sent_at, now)

            plugin.build_report
          end
        end

        def self.should_not_alert_and_should_remember_the_old_time
          it "does not send an alert about the missing machine status file" do
            plugin.build_report
            plugin.alerts.should_not include("Error: machine_status.txt is missing")
          end

          it "remembers the existing :last_missing_file_alert_sent_at" do
            mock(plugin).remember(:last_missing_file_alert_sent_at, last_missing_file_alert_sent_at)
            plugin.build_report
          end
        end
        
        before do
          File.exists?(machine_status_path).should be_false
        end

        context "when memory(:no_status_files_at) is nil" do
          before do
            mock(plugin).memory(:last_missing_file_alert_sent_at) {nil}
          end

          should_alert_and_remember_current_time
        end

        context "when memory(:last_missing_file_alert_sent_at) is within the last ScoutHonkbeatPlugin::ALERT_INTERVAL_IN_MINUTES minutes" do
          attr_reader :last_missing_file_alert_sent_at
          before do
            @last_missing_file_alert_sent_at = Time.now - ((ScoutHonkbeatPlugin::ALERT_INTERVAL_IN_MINUTES - 1) * 60)
            mock(plugin).memory(:last_missing_file_alert_sent_at) { last_missing_file_alert_sent_at }
          end

          should_not_alert_and_should_remember_the_old_time
        end

        context "when memory(:last_missing_file_alert_sent_at) is more than ScoutHonkbeatPlugin::ALERT_INTERVAL_IN_MINUTES minutes ago" do
          attr_reader :last_missing_file_alert_sent_at
          before do
            @last_missing_file_alert_sent_at = Time.now - ((ScoutHonkbeatPlugin::ALERT_INTERVAL_IN_MINUTES + 1) * 60)
            mock(plugin).memory(:last_missing_file_alert_sent_at) { last_missing_file_alert_sent_at }
          end
          
          should_alert_and_remember_current_time
        end
      end

      context "when the machine status file exists" do
        before do
          File.open(machine_status_path, "w") do |file|
            file.write([].to_json)
          end
          File.exists?(machine_status_path).should be_true
        end

        it "should not alert about a missing machine status file" do
          plugin.build_report
          plugin.alerts.should_not include("Error: machine_status.txt is missing")
        end

        context "when :last_missing_file_alert_sent_at is present" do
          before do
            mock(plugin).memory(:last_missing_file_alert_sent_at) {Time.now}
          end

          it "should not remember :last_missing_file_alert_sent_at" do
            dont_allow(plugin).remember(:last_missing_file_alert_sent_at, anything)
            plugin.build_report
          end

          it "should send an alert indicating that the machine status file is back" do
            plugin.build_report
            plugin.alerts.should include("Success: machine_status.txt is back")
          end
        end

        context "when the machine status file is less than ScoutHonkbeatPlugin::STALE_FILE_THRESHOLD_IN_MINUTES minutes old" do
          before do
            File.mtime(machine_status_path).should > (Time.now - (ScoutHonkbeatPlugin::STALE_FILE_THRESHOLD_IN_MINUTES - 1) * 60)
          end

          context "when :last_stale_file_alert_sent_at is not set" do
            it "should not alert about the age of the machine status file" do
              plugin.build_report
              plugin.alerts.should_not include("Error: machine_status.txt is stale")
            end

            it "should not remember :last_stale_file_alert_sent_at" do
              dont_allow(plugin).remember(:last_stale_file_alert_sent_at, anything)
              plugin.build_report
            end
          end

          context "when :last_stale_file_alert_sent_at is set" do
            before do
              mock(plugin).memory(:last_stale_file_alert_sent_at) {Time.now}
            end

            it "should alert that the machine_status is no longer stale" do
              plugin.build_report
              plugin.alerts.should include("Success: machine_status.txt is no longer stale")
            end

            it "should not remember :last_stale_file_alert_sent_at" do
              dont_allow(plugin).remember(:last_stale_file_alert_sent_at, anything)
              plugin.build_report
            end
          end
        end

        context "when the machine status file is more than ScoutHonkbeatPlugin::STALE_FILE_THRESHOLD_IN_MINUTES minutes old" do
          before do
            time = Time.now - ((ScoutHonkbeatPlugin::STALE_FILE_THRESHOLD_IN_MINUTES + 1) * 60)
            system "touch -t #{time.strftime('%Y%m%d%H%M.%S')} #{machine_status_path}"
            File.exists?(machine_status_path).should be_true
          end

          context "when :last_stale_file_alert_sent_at is nil" do
            it "sends an alert about the stale machine status file" do
              plugin.build_report
              plugin.alerts.should include("Error: machine_status.txt is stale")
            end

            it "remembers Time.now" do
              now = Time.now
              stub(Time).now {now}
              mock(plugin).remember(:last_stale_file_alert_sent_at, now)

              plugin.build_report
            end
          end

          context "when :last_stale_file_alert_sent_at less than ScoutHonkbeatPlugin::ALERT_INTERVAL_IN_MINUTES minutes ago" do
            attr_reader :last_stale_file_alert_sent_at
            before do
              @last_stale_file_alert_sent_at = Time.now - ((ScoutHonkbeatPlugin::ALERT_INTERVAL_IN_MINUTES - 1) * 60)
              mock(plugin).memory(:last_stale_file_alert_sent_at) {last_stale_file_alert_sent_at}
            end

            it "does not send an alert about the stale machine status file" do
              plugin.build_report
              plugin.alerts.should_not include("Error: machine_status.txt is stale")
            end

            it "remembers the existing :last_stale_file_alert_sent_at" do
              mock(plugin).remember(:last_stale_file_alert_sent_at, last_stale_file_alert_sent_at)
              plugin.build_report
            end
          end

          context "when :last_stale_file_alert_sent_at more than ScoutHonkbeatPlugin::ALERT_INTERVAL_IN_MINUTES minutes ago" do
            attr_reader :last_stale_file_alert_sent_at
            before do
              @last_stale_file_alert_sent_at = Time.now - ((ScoutHonkbeatPlugin::ALERT_INTERVAL_IN_MINUTES + 1) * 60)
              mock(plugin).memory(:last_stale_file_alert_sent_at) {last_stale_file_alert_sent_at}
            end

            it "sends an alert about the stale machine status file" do
              plugin.build_report
              plugin.alerts.should include("Error: machine_status.txt is stale")
            end

            it "remembers Time.now" do
              now = Time.now
              stub(Time).now {now}
              mock(plugin).remember(:last_stale_file_alert_sent_at, now)

              plugin.build_report
            end
          end
        end

        context "there are new errors on mongrels on this machine" do
          
        end

        context "there were mongrel errors on this machine, but they are gone now" do

        end

        context "there are no mongrel errors" do

        end
      end

    end
  end
end