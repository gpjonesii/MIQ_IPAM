require 'pg'
require 'date'


now = DateTime.now
con = PG.connect(:dbname => "#{$evm.object['db_database']}", 
                 :user => "#{$evm.object['db_user']}", 
                 :password => "#{$evm.object.decrypt('db_password')}",
                 :host => "#{$evm.object['db_hostname']}" )

res = con.exec "select hostname,ipaddr from hosts where allocated = FALSE and provisioning = FALSE limit 1;"
if res then
  $evm.log(:info, "Found an available hostname and ip address: #{res.first['hostname']} :: #{res.first['ipaddr']}")
  update = con.exec "update hosts set provisioning = TRUE , mod_date = \'#{now.year()}-#{now.mon()}-#{now.mday()} #{now.hour()}:#{now.min()}:#{now.sec()}\' where hostname = \'#{res.first['hostname']}\';"
else
  $evm.log(:info, "Couldn't get a hostname from the database")
  exit MIQ_ERROR
end

$evm.object.options[:vm_target_name] = "#{res.first['hostname']}"
$evm.object.options[:vm_target_hostname] = "#{res.first['hostname']}"
