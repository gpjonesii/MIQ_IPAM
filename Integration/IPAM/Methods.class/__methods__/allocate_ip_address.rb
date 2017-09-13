require 'pg'
require 'date'

def log_and_update_message(level, msg, update_message=false)
  $evm.log(level, "#{msg}")
  @task.message = msg if @task && (update_message || level == 'error')
end

def parse_hash(hash, options_hash=Hash.new { |h, k| h[k] = {} })
  regex = /^infoblox_nic_(\d*)_(.*)/
  hash.each do |key, value|
    if regex =~ key
      nic_index, paramter = $1.to_i, $2.to_sym
      log_and_update_message(:info, "nic_index: #{nic_index} - Adding option: {#{paramter.inspect} => #{value.inspect}} to options_hash")
      options_hash[nic_index][paramter] = value
    end
  end
  options_hash
end

def get_task_nic_options_hash(task_nic_options_hash={})
  ws_values = @task.options.fetch(:ws_values, {})
  task_nic_options_hash = parse_hash(@task.options).merge(parse_hash(ws_values))
  # no options? initialize first nic
  task_nic_options_hash[0][nil] = nil if task_nic_options_hash.blank?
  log_and_update_message(:info, "Inspecting task_nic_options_hash: #{task_nic_options_hash.inspect}")
  return task_nic_options_hash
end

def generate_unique_macaddress
  case @task.source.vendor
  when 'vmware'
    nic_prefix='00:50:56:'
  when 'redhat'
    nic_prefix='00:1a:4a:'
  end
  # Check up to 50 times for the existence of a randomly generated mac address
  for i in (1..50)
    new_macaddress = "#{nic_prefix}"+"#{("%02X" % rand(0x3F)).downcase}:#{("%02X" % rand(0xFF)).downcase}:#{("%02X" % rand(0xFF)).downcase}"
    log_and_update_message(:info, "Attempt #{i} - Checking for existence of mac_address: #{new_macaddress}")
    return new_macaddress if $evm.vmdb('vm').all.detect {|v| v.mac_addresses.include?(new_macaddress)}.nil?
  end
end

def get_operatingsystem(nic_index, template)
  os = template.try(:operating_system).try(:product_name) ||
    template.try(:hardware).try(:guest_os_full_name) ||
    template.try(:hardware).try(:guest_os) || 'unknown'
  log_and_update_message(:info, "nic_index: #{nic_index} os: #{os}")
  return os.downcase
end

def boolean(string)
  return true if string == true || string =~ (/(true|t|yes|y|1)$/i)
  return false
end

def get_network_devicetype(nic_index, nic_options)
  devicetype = $evm.object['devicetype'] || nic_options[:devicetype]
  # set your own rules here Valid NIC types (depending on vSphere version):
  # ['VirtualE1000','VirtualE1000e','VirtualPCNet32','VirtualVmxnet','VirtualVmxnet3']
  if devicetype.nil?
    if get_operatingsystem(nic_index, @task.source).include?("windows")
      if get_operatingsystem(nic_index, @task.source).include?("2012")
        devicetype = 'VirtualE1000e'
      else
        devicetype = 'VirtualE1000'
      end
    elsif get_operatingsystem(nic_index, @task.source).include?("red hat")
      devicetype = 'VirtualVmxnet3'
    elsif get_operatingsystem(nic_index, @task.source).include?("cent")
      devicetype = 'VirtualVmxnet3'
    else
      devicetype = 'VirtualE1000'
    end
  end
  log_and_update_message(:info, "nic_index: #{nic_index} devicetype: #{devicetype}")
  return devicetype
end

def get_network_vlan(nic_index, nic_options)
  vlan = $evm.object['vlan'] || nic_options[:vlan] ||
    log_and_update_message(:info, "nic_index: #{nic_index} vlan: #{vlan}")
    return vlan
end

def set_task_network_adapter_settings(nic_index, adapter_settings)
  @task.set_network_adapter(nic_index, adapter_settings)
  log_and_update_message(:info, "Provisioning object updated {:networks => #{@task.options[:networks].inspect}}")
end

def set_task_options(nic_index, hostname, fqdn, dns_servers)
  if nic_index.zero?
    @task.set_option(:dns_servers, dns_servers)
    log_and_update_message(:info, "Provisioning object updated {:dns_servers => #{@task.options[:dns_servers].inspect}}")
    @task.set_option(:vm_target_hostname, hostname)
    log_and_update_message(:info, "Provisioning object updated {:vm_target_hostname => #{@task.options[:vm_target_hostname].inspect}}")
    @task.set_option(:linux_host_name, fqdn)
    log_and_update_message(:info, "Provisioning object updated {:linux_host_name => #{@task.options[:linux_host_name].inspect}}")
  end
end

begin
  
  case $evm.root['vmdb_object_type']
  when 'vm'
    @task   = $evm.root['vm'].miq_provision
  when 'miq_provision'
    @task   = $evm.root['miq_provision']
  else
    exit MIQ_OK
  end
  log_and_update_message(:info, "Provision: #{@task.id} Request: #{@task.miq_request.id} Type:#{@task.type}")

  @created_refs = []

  now = DateTime.now
  con = PG.connect(:dbname => "#{$evm.object['db_database']}", 
                   :user => "#{$evm.object['db_user']}", 
                   :password => "#{$evm.object.decrypt('db_password')}",
                   :host => "#{$evm.object['db_hostname']}" )

  hostname = $evm.object['vm_target_name']
  res = con.exec "select hostname,ipaddr,subnet,gateway,dns1,dns2 from hosts where hostname like \'#{hostname}%\'"

  if not res
    $evm.log(:error, "Could not get IP address information for #{'hostname'}")
    exit MIQ_ERROR
  end

  fqdn = res.first['hostname']
  ipaddr = res.first['ipaddr']
  subnet = res.first['subnet']
  gateway = res.first['gateway']
  dns1 = res.first['dns1']
  dns2 = res.first['dns2']
  
  # loop through the task nic options
  get_task_nic_options_hash().each do |nic_index, nic_options|

    hostname = @task.get_option(:vm_target_hostname)

    # build nic settings hash
    nic_settings = {
      :ip_addr=> ipaddr,
      :subnet_mask=>subnet,
      :gateway=>gateway,
      :addr_mode=>["static", "Static"] 
    }
    log_and_update_message(:info, "VM: #{hostname} nic: #{nic_index} nic_settings: #{nic_settings}")
    @task.set_option(:sysprep_spec_override, 'true') unless boolean(@task.get_option(:sysprep_spec_override))
    @task.set_nic_settings(nic_index, nic_settings)
    log_and_update_message(:info, "Provisioning object updated {:nic_settings => #{@task.options[:nic_settings].inspect}}")

    # build network_ settings hash
    adapter_settings = {
      :devicetype => "VirtualE1000" #get_network_devicetype(nic_index, nic_options),
    }
#    dvs = $evm.object['distributed_virtual_switch']
#    portgroup = $evm.object['distributed_port_group']
#    @task.set_dvs("#{portgroup}")
    @task.set_network_adapter(nic_index, adapter_settings)
    log_and_update_message(:info, "VM: #{hostname} nic: #{nic_index} nic_settings: #{nic_settings} adapter_settings: #{adapter_settings}")

    # build task options
    dns_servers = "#{dns1},#{dns2}"
    set_task_options(nic_index, hostname, fqdn, dns_servers)
  end
res = con.exec "update hosts set provisioning = FALSE, allocated = TRUE, mod_date = \'#{now.year()}-#{now.mon()}-#{now.mday()} #{now.hour()}:#{now.min()}:#{now.sec()}\' where hostname like \'#{hostname}%\'"

  # Set Ruby rescue behavior
rescue => err
  log_and_update_message(:error, "[#{err}]\n#{err.backtrace.join("\n")}")
  exit MIQ_ABORT
end
