
# AutoYast routines

# List available SLES ISOs

def list_ay_isos()
  search_string = "SLES"
  list_linux_isos(search_string)
  return
end

# Configure AutoYast server

def configure_ay_server(client_arch,publisher_host,publisher_port,service_name,iso_file)
  if service_name.match(/[A-z]/)
    if service_name.downcase.match(/suse/)
      search_string = "SLES"
    end
  else
    search_string = "SLES"
  end
  configure_linux_server(client_arch,publisher_host,publisher_port,service_name,iso_file,search_string)
  return
end

# List AutoYast services

def list_ay_services()
  puts "Kickstart services:"
  service_list = Dir.entries($repo_base_dir)
  service_list.each do |service_name|
    if service_name.match(/sles/)
      puts service_name
    end
  end
  return
end

# Unconfigure AutoYast server

def unconfigure_ay_server(service_name)
  unconfigure_ks_repo(service_name)
end
