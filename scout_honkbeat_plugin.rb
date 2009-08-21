
require 'json'

class ScoutHonkbeatPlugin < Scout::Plugin
  def build_report
    host = `hostname`.strip
    machine_file_path = "/data/honk/shared/status/#{host}/machine_status.txt"
    external_dependencies_file_path = "/data/honk/shared/status/#{host}/dependency_status.txt"

    machine_status = JSON.parse(File.read(machine_file_path))
    down = []
    machine_status.each do |error|
      down << "#{error[:hostname]}:#{error[:port]}"
    end

    last_down = memory(:down)
    now_up = last_down - down
    remember(:down, down)
    alert("The following servers are now UP   : #{now_up.join(', ')}") unless now_up.empty?
    alert("The following servers are now DOWN : #{down.join(', ')}") unless down.empty?

     external_status = JSON.parse(File.read(external_dependencies_file_path))
    down_external = []
    last_external_down = memory(:down_external)
    external_status.each do |error|
      down_external << "#{error[:name]}:#{error[:type]}"
    end
    now_up_external = last_external_down - down_external
    alert("The following external dependencies are now UP   : #{now_up_external.join(', ')}") unless now_up_external.empty?
    alert("The following external dependencies are now DOWN : #{down_external.join(', ')}") unless down_external.empty?

    remember(:down_external, down_external)
  end
end