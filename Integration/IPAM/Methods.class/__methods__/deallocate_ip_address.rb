require 'pg'
require 'date'


now = DateTime.now
con = PG.connect(:dbname => "#{$evm.object['db_database']}", 
  :user => "#{$evm.object['db_user']}", 
  :password => "#{$evm.object.decrypt('db_password')}",
  :host => "#{$evm.object['db_hostname']}" )

hostname = $evm.object['vm_target_name']
res = con.exec "update hosts set provisioning = FALSE, allocated = FALSE, mod_date = \'#{now.year()}-#{now.mon()}-#{now.mday()} #{now.hour()}:#{now.min()}:#{now.sec()}\' where hostname like \'#{hostname}%\'"

if not res
  $evm.log(:info, "WARNING! Could not deallocate IP address information for #{'hostname'}")
  exit MIQ_OK
end

$evm.log(:info, "IP address deallocated for #{'hostname'}")
