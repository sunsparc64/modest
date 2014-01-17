
# Server code for Kickstart

# Process ISO file to get details

def get_linux_version_info(iso_file_name)
  iso_info     = File.basename(iso_file_name)
  iso_info     = iso_info.split(/-/)
  linux_distro = iso_info[0]
  linux_distro = linux_distro.downcase
  if linux_distro.match(/centos|ubuntu|sles/)
    if linux_distro.match(/sles/)
      iso_version = iso_info[1]+"."+iso_info[2]
      iso_version = iso_version.gsub(/SP/,"")
    else
      iso_version = iso_info[1]
    end
    if linux_distro.match(/centos/)
      iso_arch = iso_info[2]
    else
      if linux_distro.match(/sles/)
        iso_arch  = iso_info[4]
      else
        iso_arch = iso_info[3]
        iso_arch = iso_arch.split(/\./)[0]
        if iso_arch.match(/amd64/)
          iso_arch  = "x86_64"
        else
          iso_arch  = "i386"
        end
      end
    end
  else
    iso_version = iso_info[2]
    iso_arch    = iso_info[3]
  end
  return linux_distro,iso_version,iso_arch
end

# List available ISOs

def list_ks_isos()
  search_string = "CentOS|rhel|ubuntu|SLES"
  iso_list      = check_iso_base_dir(search_string)
  iso_list.each do |iso_file_name|
    iso_file_name = iso_file_name.chomp
    (linux_distro,iso_version,iso_arch) = get_linux_version_info(iso_file_name)
    puts "ISO file:\t"+iso_file_name
    puts "Distribution:\t"+linux_distro
    puts "Version:\t"+iso_version
    puts "Architecture:\t"+iso_arch
    iso_version      = iso_version.gsub(/\./,"_")
    service_name     = linux_distro+"_"+iso_version+"_"+iso_arch
    repo_version_dir = $repo_base_dir+"/"+service_name
    if File.directory?(repo_version_dir)
      puts "Service Name:\t"+service_name+" (exists)"
    else
      puts "Service Name:\t"+service_name
    end
  end
  return
end

# Unconfigure alternate packages

def unconfigure_ks_alt_repo(service_name)
  return
end

# Configure alternate packages

def configure_ks_alt_repo(service_name,client_arch)
  rpm_list = build_ks_alt_rpm_list(service_name)
  alt_dir  = $repo_base_dir+"/"+service_name+"/alt"
  check_dir_exists(alt_dir)
  rpm_list.each do |rpm_url|
    rpm_file = File.basename(rpm_url)
    rpm_file = alt_dir+"/"+rpm_file
    if !File.exists?(rpm_file)
      wget_file(rpm_url,rpm_file)
    end
  end
  return
end

# Unconfigure Linux repo

def unconfigure_ks_repo(service_name)
  remove_apache_alias(service_name)
  repo_version_dir = $repo_base_dir+"/"+service_name
  destroy_zfs_fs(repo_version_dir)
  return
end

# Copy Linux ISO contents to

def configure_ks_repo(iso_file,repo_version_dir)
  check_zfs_fs_exists(repo_version_dir)
  check_dir = repo_version_dir+"/isolinux"
  if $verbose_mode == 1
    puts "Checking:\tDirectory "+check_dir+" exits"
  end
  if !File.directory?(check_dir)
    mount_iso(iso_file)
    copy_iso(iso_file,repo_version_dir)
    umount_iso()
  end
  return
end

# Unconfigure Kickstart server

def unconfigure_ks_server(service_name)
  unconfigure_ks_repo(service_name)
end

# Configure PXE boot

def configure_ks_pxe_boot(service_name,iso_arch)
  pxe_boot_dir = $tftp_dir+"/"+service_name
  if service_name.match(/centos|rhel|sles/)
    test_dir     = pxe_boot_dir+"/usr"
    if !File.directory?(test_dir)
      if service_name.match(/centos/)
        rpm_dir = $repo_base_dir+"/"+service_name+"/CentOS"
      else
        if service_name.match(/sles/)
          rpm_dir = $repo_base_dir+"/"+service_name+"/suse"
        else
          rpm_dir = $repo_base_dir+"/"+service_name+"/Packages"
        end
      end
      if File.directory?(rpm_dir)
        message  = "Locating:\tSyslinux package"
        command  = "cd #{rpm_dir} ; find . -name 'syslinux*' |grep '#{iso_arch}'"
        output   = execute_command(message,command)
        rpm_file = output.chomp
        rpm_file = rpm_file.gsub(/\.\//,"")
        rpm_file = rpm_dir+"/"+rpm_file
        check_dir_exists(pxe_boot_dir)
        message = "Copying:\tPXE boot files from "+rpm_file+" to "+pxe_boot_dir
        command = "cd #{pxe_boot_dir} ; #{$rpm2cpio_bin} #{rpm_file} | cpio -iud"
        output  = execute_command(message,command)
      else
        puts "Warning:\tSource directory "+rpm_dir+" does not exist"
        exit
      end
    end
    pxe_image_dir=pxe_boot_dir+"/images"
    if !File.directory?(pxe_image_dir)
      if service_name.match(/sles/)
        iso_image_dir = $repo_base_dir+"/"+service_name+"/boot"
      else
        iso_image_dir = $repo_base_dir+"/"+service_name+"/images"
      end
      message       = "Copying:\tPXE boot images from "+iso_image_dir+" to "+pxe_image_dir
      command       = "cp -r #{iso_image_dir} #{pxe_boot_dir}"
      output        = execute_command(message,command)
    end
  else
    check_dir_exists(pxe_boot_dir)
    pxe_image_dir = pxe_boot_dir+"/images"
    check_dir_exists(pxe_image_dir)
    pxe_image_dir = pxe_boot_dir+"/images/pxeboot"
    check_dir_exists(pxe_image_dir)
    iso_image_dir = $repo_base_dir+"/"+service_name+"/install"
    if !File.directory?(pxe_image_dir)
      message = "Copying:\tPXE boot files from "+iso_image_dir+" to "+pxe_image_dir
      command = "cd #{pxe_image_dir} ; cp -r #{iso_image_dir}/* . "
      output  = execute_command(message,command)
    end
  end
  pxe_cfg_dir = $tftp_dir+"/pxelinux.cfg"
  check_dir_exists(pxe_cfg_dir)
  return
end

# Unconfigure PXE boot

def unconfigure_ks_pxe_boot(service_name)
  return
end

# Configure Kickstart server

def configure_ks_server(client_arch,publisher_host,publisher_port,service_name,iso_file)
  if service_name.match(/[A-z]/)
    if service_name.downcase.match(/centos/)
      search_string = "CentOS"
    end
    if service_name.downcase.match(/sles/)
      search_string = "SLES"
    end
    if service_name.downcase.match(/redhat/)
      search_string = "rhel"
    end
  else
    search_string = "CentOS|rhel|ubuntu|SLES"
  end
  if iso_file.match(/[A-z]/)
    if File.exists?(iso_file)
      iso_list[0] = iso_file
    else
      puts "Warning:\tISO file "+is_file+" does not exist"
    end
  else
    iso_list=check_iso_base_dir(search_string)
  end
  if iso_list[0]
    iso_list.each do |iso_file_name|
      iso_file_name=iso_file_name.chomp
      (linux_distro,iso_version,iso_arch) = get_linux_version_info(iso_file_name)
      iso_version = iso_version.gsub(/\./,"_")
      service_name      = linux_distro+"_"+iso_version+"_"+iso_arch
      repo_version_dir  = $repo_base_dir+"/"+service_name
      add_apache_alias(service_name)
      configure_ks_repo(iso_file_name,repo_version_dir)
      configure_ks_pxe_boot(service_name,iso_arch)
    end
  else
    add_apache_alias(service_name)
    configure_ks_repo(iso_file,repo_version_dir)
    configure_ks_pxe_boot(service_name)
  end
  return
end

# List kickstart services

def list_ks_services()
  puts "Kickstart services:"
  service_list = Dir.entries($repo_base_dir)
  service_list.each do |service_name|
    if service_name.match(/centos|rhel|ubuntu|sles/)
      puts service_name
    end
  end
  return
end
