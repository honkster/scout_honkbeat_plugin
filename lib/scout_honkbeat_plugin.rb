require 'json'

class ScoutHonkbeatPlugin < Scout::Plugin
  STALE_FILE_THRESHOLD_IN_MINUTES = 10
  ALERT_INTERVAL_IN_MINUTES = 30

  def build_report
    no_machine_status_file_at = memory(:last_missing_file_alert_sent_at)

    if machine_file_exists?
      if no_machine_status_file_at
        alert("Success: machine_status.txt is back")
      end

      stale_status_file_at = memory(:last_stale_file_alert_sent_at)
      if machine_file_is_current?
        if stale_status_file_at
          alert("Success: machine_status.txt is no longer stale")
        end
        check_machine_status
        report(report_data)
      else
        if alert_interval_exceeded?(stale_status_file_at)
          alert("Error: machine_status.txt is stale")
          remember(:last_stale_file_alert_sent_at, Time.now)
        else
          remember(:last_stale_file_alert_sent_at, stale_status_file_at)
          logger.info "Ignoring notification for stale status files, less than #{ALERT_INTERVAL_IN_MINUTES} minutes apart"
        end
      end
    else
      if alert_interval_exceeded?(no_machine_status_file_at)
        alert("Error: machine_status.txt is missing")
        remember(:last_missing_file_alert_sent_at, Time.now)
      else
        remember(:last_missing_file_alert_sent_at, no_machine_status_file_at)
        logger.info "Ignoring notification for no status files, less than #{ALERT_INTERVAL_IN_MINUTES} minutes apart"
      end
    end
  end

  def check_machine_status
    machine_status = JSON.parse(File.read(machine_file_path))
    down = machine_status.map do |error|
      "#{error['hostname']}:#{error['port']}"
    end

    last_down = memory(:down)
    remember(:down, down)

    now_up   = []
    now_up   = last_down - down if last_down
    down     = down - last_down if last_down

    report_data["Server Errors"] = down.join(', ')
    alert("The following servers are now UP   : #{now_up.join(', ')}") unless now_up.empty?
    alert("The following servers are now DOWN : #{down.join(', ')}") unless down.empty?
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