require 'pg'
require 'date'


now = DateTime.now
con = PG.connect(:dbname => "#{$evm.object['db_database']}", 
  :user => "#{$evm.object['db_user']}", 
  :password => "#{$evm.object.decrypt('db_password')}",
  :host => "#{$evm.object['db_hostname']}" )

vm = $evm.root['vm']
hostname = vm.name
if hostname then
  res = con.exec "update hosts set provisioning = FALSE, allocated = FALSE, mod_date = \'#{now.year()}-#{now.mon()}-#{now.mday()} #{now.hour()}:#{now.min()}:#{now.sec()}\' where hostname like \'#{hostname}%\'"

  if not res
    $evm.log(:info, "WARNING! Could not deallocate IP address information for #{'hostname'}")
    exit MIQ_OK
  end
else
  $evm.log(:info, "WARNING! Could not get hostname from $evm")
  exit MIQ_ERROR
end
  
$evm.log(:info, "IP address deallocated for #{'hostname'}")
