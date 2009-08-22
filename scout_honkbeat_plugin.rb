
require 'json'

class ScoutHonkbeatPlugin < Scout::Plugin
  
  def build_report
    
    host = `hostname`.strip
    machine_file_path = "/data/honk/shared/status/#{host}/machine_status.txt"
    external_dependencies_file_path = "/data/honk/shared/status/#{host}/dependency_status.txt"

    machine_status = JSON.parse(File.read(machine_file_path))[0]
    external_status = JSON.parse(File.read(external_dependencies_file_path))

    down = machine_status.map do |error|
      "#{error['hostname']}:#{error['port']}"
    end

    last_down = memory(:down)
    remember(:down, down)

    now_up   = []
    now_up   = last_down - down if last_down
    down     = down - last_down if last_down

    #shouldnt fire on empty... but is
    alert("The following servers are now UP   : #{now_up.join(', ')}") unless now_up.empty?
    alert("The following servers are now DOWN : #{down.join(', ')}") unless down.empty?

    down_external = external_status.map do |error|
      "#{error['name']}:#{error['type']}"
    end

    last_down_external = memory(:down_external)
    remember(:down_external, down_external)

    now_up_external = []
    now_up_external = last_down_external - down_external if last_down_external
    down_external   = down_external - last_down_external if last_down_external

    alert("The following external dependencies are now UP   : #{now_up_external.join(', ')}") unless now_up_external.empty?
    alert("The following external dependencies are now DOWN : #{down_external.join(', ')}") unless down_external.empty?
  
  end
end