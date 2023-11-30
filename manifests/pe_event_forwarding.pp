# @summary This class adds the event forwarding processor to send PE event data
#
# @example
#   include datadog_agent::pe_event_forwarding
class datadog_agent::pe_event_forwarding {
  if $pe_event_forwarding::confdir != undef {
    $confdir_base_path = $pe_event_forwarding::confdir
  }
  else {
    $confdir_base_path = pe_event_forwarding::base_path($settings::confdir, undef)
  }

  file { "${confdir_base_path}/pe_event_forwarding/processors.d/datadog_pe_events.rb":
    ensure  => file,
    owner   => 'pe-puppet',
    group   => 'pe-puppet',
    mode    => '0755',
    source  => 'puppet:///modules/datadog_agent/datadog_pe_events.rb',
    require => [
      Class['pe_event_forwarding'],
      Class['datadog_agent::reports'],
    ],
  }
}
