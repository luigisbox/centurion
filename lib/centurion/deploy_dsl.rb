require_relative 'docker_server_group'
require_relative 'docker_server'
require 'uri'

module Centurion::DeployDSL
  def on_each_docker_host(&block)
    build_server_group.tap { |hosts| hosts.each { |host| block.call(host) } }
  end

  def env_vars(new_vars)
    service_under_construction.add_env_vars(new_vars)
  end

  def host(hostname)
    current = fetch(:hosts, [])
    current << hostname
    set(:hosts, current)
  end

  def memory(memory)
    service_under_construction.memory = memory
  end

  def cpu_shares(cpu_shares)
    service_under_construction.cpu_shares = cpu_shares
  end

  def command(command)
    service_under_construction.command = command
  end

  def localhost
    # DOCKER_HOST is like 'tcp://127.0.0.1:2375'
    docker_host_uri = URI.parse(ENV['DOCKER_HOST'] || "tcp://127.0.0.1")
    host_and_port = [docker_host_uri.host, docker_host_uri.port].compact.join(':')
    host(host_and_port)
  end

  def host_port(port, options)
    validate_options_keys(options, [ :host_ip, :container_port, :type ])
    require_options_keys(options,  [ :container_port ])

    service_under_construction.add_port_bindings(port, options[:container_port], options[:type] || 'tcp', options[:host_ip])
  end

  def host_volume(volume, options)
    validate_options_keys(options, [ :container_volume ])
    require_options_keys(options,  [ :container_volume ])

    container_volume = options[:container_volume]

    service_under_construction.add_volume(volume, container_volume)
  end

  def get_current_tags_for(image)
    build_server_group.inject([]) do |memo, target_server|
      tags = target_server.current_tags_for(image)
      memo += [{ server: target_server.hostname, tags: tags }] if tags
      memo
    end
  end

  def registry(type)
    set(:registry, type.to_s)
  end

  def health_check(method)
   abort("Health check expects a callable (lambda, proc, method), but #{method.class} was specified")  unless method.respond_to?(:call)
   set(:health_check, method)
  end

  #def service(name, &block)
  #  services = fetch(:services, {})
  #  service = services.fetch(name) { Service.new(name) }
  #  set(:service_under_construction, service)
  #  block.call
  #  services[name] = service
  #  set(:services, services)
  #  set(:service_under_construction, services.fetch(:default))
  #end

 # def service_under_construction
 #   service = fetch(:service_under_construction)
 #   unless service
 #     services = fetch(:services, {})
 #     service = services[:default]
 #     unless service
 #       service = Centurion::Service.new(:default)
 #       services[:default] = service
 #       set(:services, services)
 #     end
 #   end
 #   service
 # end

 # def defined_services
 #   fetch(:services, {}).values.map do |service|
 #     service.image_id = fetch(:image)
 #     service.hostname = fetch(:container_hostname)
 #     service.dns = fetch(:custom_dns)
 #   end
 #end

  def defined_service
    service = fetch(:service, {})
    service.image = fetch(:image)
    service.hostname = fetch(:container_hostname)
    service.dns = fetch(:custom_dns)
    service
  end

  def defined_health_check
    Centurion::HealthCheck.new(fetch(:health_check, Centurion::HttpHealthCheck.new),
                               fetch(:status_endpoint, '/'),
                               fetch(:rolling_deploy_wait_time, 5),
                               fetch(:rolling_deploy_retries, 24))
  end

  def defined_restart_policy
    Centurion::Service::RestartPolicy.new(fetch(:restart_policy_name, 'on-failure'), fetch(:restart_policy_max_retry_count, 10))
  end

  private

  def service_under_construction
    service = fetch(:service, Centurion::Service.new(fetch(:project)))
    set(:service, service)
  end


  def build_server_group
    hosts, docker_path = fetch(:hosts, []), fetch(:docker_path)
    Centurion::DockerServerGroup.new(hosts, docker_path, build_tls_params)
  end

  def validate_options_keys(options, valid_keys)
    unless options.keys.all? { |k| valid_keys.include?(k) }
      raise ArgumentError.new('Options passed with invalid key!')
    end
  end

  def require_options_keys(options, required_keys)
    missing = required_keys.reject { |k| options.keys.include?(k) }

    unless missing.empty?
      raise ArgumentError.new("Options must contain #{missing.inspect}")
    end
  end

  def tls_paths_available?
    Centurion::DockerViaCli.tls_keys.all? { |key| fetch(key).present? }
  end

  def build_tls_params
    return {} unless fetch(:tlsverify)
    {
      tls: fetch(:tlsverify || tls_paths_available?),
      tlscacert: fetch(:tlscacert),
      tlscert: fetch(:tlscert),
      tlskey: fetch(:tlskey)
    }
  end
end
