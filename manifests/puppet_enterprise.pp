# @summary This class adds event reporting and service check integrations for Puppet Enterprise
#
# @example
#   include datadog_agent::puppet_enterprise
class datadog_agent::puppet_enterprise (
  Boolean $event_reporting = false,
  Boolean $service_checks = false,
  Optional[String] $check_interval = '2',
){
  if $event_reporting {
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
  if $service_checks {
    file { '/etc/puppetlabs/datadog':
      ensure => directory,
      owner  => 'pe-puppet',
      group  => 'pe-puppet',
    }

    file { '/etc/puppetlabs/datadog/pe_service_checks.rb':
      ensure  => file,
      owner   => 'pe-puppet',
      group   => 'pe-puppet',
      mode    => '0755',
      require => File['/etc/puppetlabs/datadog'],
      source  => 'puppet:///modules/datadog_agent/pe_service_checks.rb',
    }

    cron { 'pe_service_checks':
      ensure  => present,
      command => '/etc/puppetlabs/datadog/pe_service_checks.rb',
      user    => 'pe-puppet',
      minute  => "*/${check_interval}",
      require => File['/etc/puppetlabs/datadog/pe_service_checks.rb'],
    }
  }
}
