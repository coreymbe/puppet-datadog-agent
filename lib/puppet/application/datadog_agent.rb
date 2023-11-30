require 'puppet'
require 'puppet/application'
require 'dogapi'

class Puppet::Application::Datadog_agent < Puppet::Application

  RUN_HELP = _("Run 'puppet datadog_agent --help' for more details").freeze

  run_mode :master

  # Options for datadog_agent

  option('--pe_metrics')
  option('--debug', '-d')

  def dd_config
    configfile = '/etc/datadog-agent/datadog-reports.yaml'
    config = YAML.load_file(configfile)
  end

  def get_name(servername)
    name = if servername.to_s == '127-0-0-1'
             Puppet[:certname].to_s
           else
             servername
           end
    name.to_s
  end

  def filter_metrics(base_metrics, filters)
    extract = {}
    filtered = {}
    filters.each do |filter|
      path = filter.split('.')
      next unless path[0] == base_metrics.keys[0]
      stat = path[-2] == base_metrics.keys[0] ? path[-1] : path[-2]
      extracted = extract_data(extract, base_metrics, path)
      extracted.each do |data, metrics|
        metrics.each do |metric, value|
          if stat == data
            filtered["#{data}.#{metric}"] = value
          else
            filtered["#{stat}.#{data}.#{metric}"] = value
          end
        end
      end
    end unless filters.nil?
    filtered
  end

  def extract_data(final_data, data, path)
    if path.count == 1
      if data[path[0]].nil?
        Puppet.debug "ERROR with last FILTER KEY #{path[0]}; Check your filter parameter"
      end
      final_data[path[0]] = data[path[0]]
      final_data
    else
      begin
        dig_result          = data.dig(*path[0,1])
        final_data[path[0]] = {}
        extract_data(final_data[path[0]], dig_result, path[1..-1])
      rescue => e
        Puppet.debug "Potential ERROR with middle FILTER KEY #{path[1..-1]}: #{e.backtrace}"
      end
    end
  end

  def parse_metrics(metrics, server, service, filters)
    all_metrics = {}
    base_metrics = metrics['servers'][server]
    jvm_services = ['console','orchestrator','puppetdb','puppetserver']

    # JVM Metrics
    if jvm_services.include?(service)
      jvm_metrics = base_metrics[service]['status-service']['status']['experimental']['jvm-metrics']
      jvm_metrics.each do |metric, value|
        all_metrics[metric] = value
      end
      jvm_metrics['heap-memory'].each do |metric, value|
        all_metrics["heap-memory.#{metric}"] = value
      end
      jvm_metrics['non-heap-memory'].each do |metric, value|
        all_metrics["non-heap-memory.#{metric}"] = value
      end
    end

    # Ace & Bolt Metrics
    if (service == 'ace') || (service == 'bolt')
      base_metrics[service].each do |metric, value|
        all_metrics[metric] = value
      end
      base_metrics[service]['gc_stats'].each do |metric, value|
        all_metrics["gc_stats.#{metric}"] = value
      end
    end

    # PuppetDB Metrics
    if service == 'puppetdb'
      all_metrics['queue_depth'] = base_metrics[service]['puppetdb-status']['status']['queue_depth']
      stats = ['global_processing-time', 'global_processed', 'storage_replace-catalog-time', 'storage_replace-facts-time', 'storage_store-report-time', 'PDBReadPool_pool_Usage', 'PDBReadPool_pool_Wait', 'PDBReadPool_pool_PendingConnections', 'PDBWritePool_pool_Usage', 'PDBWritePool_pool_Wait', 'PDBWritePool_pool_PendingConnections']
      stats.each do |stat|
        base_metrics[service][stat].each do |metric, value|
          all_metrics["#{stat}.#{metric}"] = value
        end
      end
    end

    # Puppet Server Metrics
    if service == 'puppetserver'
      jruby_metrics = base_metrics[service]['jruby-metrics']['status']['experimental']['metrics']
      jruby_metrics.each do |metric, value|
        all_metrics[metric] = value
      end
      jruby_metrics['borrow-timers'].each do |endpoint, metrics|
        metrics.each do |metric, value|
          all_metrics["borrow-timers.#{endoint}.#{metric}"] = value
        end
      end
    end

    # Postgres Metrics
    if service == 'postgres'
      pg_metrics = base_metrics[service]['databases']
      pg_metrics.each_key do |db|
        pg_metrics[db].each_key do |stats|
          unless stats == 'database_stats'
            pg_metrics[db][stats].each_key do |table|
              pg_metrics[db][stats][table].each do |metric, value|
                all_metrics["#{db}.#{stats}.#{table}.#{metric}"] = value
              end
            end
          end
        end
        pg_metrics[db]['database_stats'].each do |metric, value|
          all_metrics["#{db}.database_stats.#{metric}"] = value
        end
      end
    end

    # Additional Metrics
    filtered_metrics = filter_metrics(base_metrics, filters)
    filtered_metrics.each do |metric, value|
        all_metrics[metric] = value
    end unless filtered_metrics.nil?
    all_metrics
  end

  def send_pe_metrics(data)
    settings = dd_config
    server = data['servers'].keys[0]
    service = data['servers'][server].keys[0]
    all_metrics = parse_metrics(data, server, service, settings[:metric_filters])

    # Configure the Dog
    api_key    = settings[:datadog_api_key]
    api_url    = settings[:api_url]
    dog = Dogapi::Client.new(api_key, nil, server, nil, nil, nil, api_url)

    Puppet.info 'Submitting metrics to DataDog'
    dog.batch_metrics do
      all_metrics.each do |metric, val|
        next unless (val.is_a?(Integer) || val.is_a?(Float))
        name = "puppet.#{service}.#{metric}"
        value = val
        dog.emit_point(name.to_s, value, host: server, tags: ["puppet-#{service}"])
      end
    end
  end

  def main
    data = STDIN.lines.map {|l| JSON.parse(l)}
    data.each do |server|
      send_pe_metrics(server) if options[:pe_metrics]
    end
  end
end
