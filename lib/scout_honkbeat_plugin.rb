require 'json'

class ScoutHonkbeatPlugin < Scout::Plugin
  STALE_FILE_THRESHOLD_IN_MINUTES = 10
  ALERT_INTERVAL_IN_MINUTES = 30

  def build_report
    on_machine_file_exists do
      on_machine_file_is_fresh do
        check_machine_status
        report(report_data)
      end
    end
  end

  def on_machine_file_exists
    last_missing_file_alert_sent_at = memory(:last_missing_file_alert_sent_at)
    if machine_file_exists?
      if last_missing_file_alert_sent_at
        alert("Success: machine_status.txt is back")
      end
      yield
    else
      send_error_if_inverval_exceeded(last_missing_file_alert_sent_at, :last_missing_file_alert_sent_at,
                                      "Error: machine_status.txt is missing")
    end
  end

  def on_machine_file_is_fresh
    last_stale_file_alert_sent_at = memory(:last_stale_file_alert_sent_at)
    if machine_file_is_current?
      if last_stale_file_alert_sent_at
        alert("Success: machine_status.txt is no longer stale")
      end
      yield
    else
      send_error_if_inverval_exceeded(last_stale_file_alert_sent_at, :last_stale_file_alert_sent_at,
                                      "Error: machine_status.txt is stale")
    end
  end

  def send_error_if_inverval_exceeded(last_alert_sent_at, last_alert_sent_at_name, error_message)
    if alert_interval_exceeded?(last_alert_sent_at)
      alert(error_message)
      remember(last_alert_sent_at_name, Time.now)
    else
      remember(last_alert_sent_at_name, last_alert_sent_at)
      logger.info "Ignoring notification for '#{error_message}', less than #{ALERT_INTERVAL_IN_MINUTES} minutes apart"
    end
  end

  def check_machine_status
    machine_status = JSON.parse(File.read(machine_file_path))
    down = machine_status.map do |error|
      error['checks'].keys.map do |service|
        "- #{service} on #{error['hostname']}:#{error['port']}"
      end
    end.flatten.sort

    last_down = memory(:down)
    remember(:down, down)

    now_up   = []
    now_up   = last_down - down if last_down

    report_data["Services Down"] = down.length
    alert("Success: The following services are UP:\n#{now_up.join("\n")}") unless now_up.empty?

    last_machine_error_alert_sent_at = memory(:last_machine_error_alert_sent_at)
    if !down.empty? && (last_down != down || alert_interval_exceeded?(last_machine_error_alert_sent_at))
      alert("Error: The following services are DOWN:\n#{down.join("\n")}")
      remember(:last_machine_error_alert_sent_at, Time.now)
    else
      remember(:last_machine_error_alert_sent_at, last_machine_error_alert_sent_at)
    end
  end

  def alert_interval_exceeded?(last_time)
    return true unless last_time
    last_time < (Time.now - ALERT_INTERVAL_IN_MINUTES * 60)
  end

  def machine_file_is_current?
    File.mtime(machine_file_path) >= earliest_current_time
  end

  def machine_file_exists?
    File.exists?(machine_file_path)
  end

  def earliest_current_time
    Time.now - (STALE_FILE_THRESHOLD_IN_MINUTES * 60)
  end

  def host
    @host ||= `hostname`.strip
  end

  def machine_file_path
    "#{status_path}/machine_status.txt"
  end

  def status_path
    "/data/honk/shared/status/#{host}"
  end

  def report_data
    @report_data ||= {}
  end
end
