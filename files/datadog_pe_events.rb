#!/opt/puppetlabs/puppet/bin/ruby

require 'json'
require 'dogapi'

configfile = '/etc/datadog-agent/datadog-reports.yaml'
settings = YAML.load_file(configfile)

server = settings[:pe_console]
api_key    = settings[:datadog_api_key]
api_url    = settings[:api_url]

data_path = ARGV[0]
data = JSON.parse(File.read(data_path))
dog = Dogapi::Client.new(api_key, nil, server, nil, nil, nil, api_url)

events = {
  'orchestrator' => 'PE Orchestrator',
  'rbac'         => 'RBAC',
  'classifier'   => 'Classifier',
  'pe-console'   => 'PE Console',
  'code-manager' => 'Code Manager'
}

event_types = events.select { |type| settings[:pe_event_types].include? type }
event_types.each do |index, service|
  # A nil value indicates that there were no new events.
  # A negative value indicates that the sourcetype has been disabled from the pe_event_forwarding module.
  next if data[index].nil? || data[index] == -1
  data[index]['events'].each do |event_data|
    event = JSON.pretty_generate(event_data)
    event_title = "Puppet #{service} Event"
    res = dog.emit_event(Dogapi::Event.new(event,
                                     msg_title: event_title,
                                     event_type: "puppet.#{index}",
                                     alert_type: 'info',
                                     priority: 'low',
                                     source_type_name: 'puppet'),
                  host: server)
    if res[0] != 202
      puts "#{service} event sent to Datadog"
    else
      puts "Failed to send event to Datadog: #{res[0]} Bad Request!"
    end
  end
end
