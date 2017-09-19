require 'pg'
require 'date'

def populate_dialog_element(string)
  dialog_element = $evm.object
  
  list_values = {
    'required'   => true,
    'protected'   => false,
    'read_only'  => true,
    'value' => string,
  }
  
  list_values.each do |key, value| 
    dialog_element[key] = value
  end
end

now = DateTime.now
con = PG.connect(:dbname => "#{$evm.object['db_database']}", 
                 :user => "#{$evm.object['db_user']}", 
                 :password => "#{$evm.object.decrypt('db_password')}",
                 :host => "#{$evm.object['db_hostname']}" )

res = con.exec "select hostname,ipaddr from hosts where allocated = FALSE and provisioning = FALSE limit 1;"
if res then
  $evm.log(:info, "Found an available hostname and ip address: #{res.first['hostname']} :: #{res.first['ipaddr']}")
  update = con.exec "update hosts set provisioning = TRUE, mod_date = \'#{now.year()}-#{now.mon()}-#{now.mday()} #{now.hour()}:#{now.min()}:#{now.sec()}\' where hostname = \'#{res.first['hostname']}\';"
else
  $evm.log(:info, "Couldn't get a hostname from the database")
  exit MIQ_ERROR
end

dialog_element_value = "#{res.first['hostname']}"
populate_dialog_element(dialog_element_value)

con.close()

exit MIQ_OK
