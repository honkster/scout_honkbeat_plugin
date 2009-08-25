
require 'json'

class ScoutHonkbeatPlugin < Scout::Plugin

  def build_report
    if report_files_exist?
      process_report_files
    else
      last_files_alert  = memory(:no_status_files_at)
      if(last_files_alert.nil? || (Time.now -last_files_alert)/60 > 30.0)
        alert("There are no status files available")
        remember(:no_status_files_at =>Time.now)
      else
        logger.info "Ignoring notification for no status files, less than 30 minutes apart"
      end
    end
  end

  def process_report_files
    check_server_health
    check_external_services
    report(report_data)
  end

  def report_files_exist?
    File.exists?(machine_file_path) && File.exists?(external_dependencies_file_path)
  end

  def check_server_health
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

  def check_external_services
    external_status = JSON.parse(File.read(external_dependencies_file_path))

    down_external = external_status.map do |error|
      "#{error['name']}:#{error['type']}"
    end

    last_down_external = memory(:down_external)
    remember(:down_external, down_external)

    now_up_external = []
    now_up_external = last_down_external - down_external if last_down_external
    down_external   = down_external - last_down_external if last_down_external

    report_data["External Service Errors"] = down_external.join(', ')
    alert("The following external dependencies are now UP   : #{now_up_external.join(', ')}") unless now_up_external.empty?
    alert("The following external dependencies are now DOWN : #{down_external.join(', ')}") unless down_external.empty?
  end

  def host
    @host ||= `hostname`.strip
  end

  def machine_file_path
    "/data/honk/shared/status/#{host}/machine_status.txt"
  end

  def external_dependencies_file_path
    "/data/honk/shared/status/#{host}/dependency_status.txt"
  end

  def report_data
    @report_data ||= {}
  end
end