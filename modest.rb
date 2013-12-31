#!/usr/bin/env ruby

# Name:         modest (Muti OS Deployment Engine Server Tool)
# Version:      0.6.4
# Release:      1
# License:      Open Source
# Group:        System
# Source:       N/A
# URL:          http://lateralblast.com.au/
# Distribution: UNIX
# Vendor:       Lateral Blast
# Packager:     Richard Spindler <richard@lateralblast.com.au>
# Description:  Script to automate creation of server configuration for
#               Solaris and other OS

# Additional notes:
#
# - Swapped Dir.exits for File.directory so ruby 2.x is not required
# - Swapped Dir.home for ENV["HOME"] so ruby 2.x is not required

require 'rubygems'
require 'getopt/std'
require 'builder'

# Set up some global variables/defaults

$script=$0
$options="F:a:c:d:e:f:h:i:n:p:z:ACDJKLMPRSVWZtv"
$verbose_mode=0
$test_mode=0
$iso_base_dir="/export/isos"
$repo_base_dir="/export/repo"
$iso_mount_dir="/cdrom"
$ai_base_dir="/export/auto_install"
$work_dir=""
$tmp_dir=""
$alt_repo_name="alt"
$alt_prefix_name="solaris"
$home_dir=ENV["HOME"]
$default_zpool="rpool"
$default_ai_port="10081"
$default_host=""
$default_net="net0"
$default_timezone="Australia/Victoria"
$default_terminal="sun"
$default_keymap="US-English"
$default_environment="en_US.UTF-8"
$default_nameserver="8.8.8.8"
$default_netmask="255.255.255.0"
$default_search="local"
$default_files="files"
$default_hosts="files dns"
$default_root_password="XXXX"
$default_admin_password="YYYY"
$use_alt_repo=0
$destroy_fs=0
$use_defaults=0
$default_apache_allow=""
$default_admin_user="sysadmin"
$default_admin_group="wheel"
$default_admin_home="/export/home"
$default_admin_shell="/export/home"
$default_admin_uid="200"
$tftp_dir="/etc/netboot"

# Declare some package versions

$facter_version="1.7.4"
$hiera_version="1.3.0"
$puppet_version="3.4.1"

# Load methods

if File.directory?("./methods")
  file_list=Dir.entries("./methods")
  for file in file_list
    if file =~/rb$/
      require "./methods/#{file}"
    end
  end
end

# Print script usage information

def print_usage()
  puts ""
  puts "Usage: "+$script+" -["+$options+"]"
  puts ""
  puts "-h: Display usage"
  puts "-c: Create client"
  puts "-V: Display version"
  puts "-A: Configure AI"
  puts "-J: Configure Jumpstart"
  puts "-K: Configure Kicstart"
  puts "-M: Maintenance mode"
  puts "-a: Architecture"
  puts "-e: Client MAC Address"
  puts "-i: Clinet IP Address"
  puts "-S: Configure server"
  puts "-C: Configure client services"
  puts "-p: Puplisher server port number"
  puts "-h: Puplisher server Hostname/IP"
  puts "-t: Run it test mode (in client mode create files but don't import them)"
  puts "-v: Run in verbose mode"
  puts "-f: ISO file to use"
  puts "-F: Set location of ISOs (directory)"
  puts "-d: Delete client"
  puts "-n: Set service name"
  puts "-z: Delete service name"
  puts "-M: Maintenance operations"
  puts "-P: Configure PXE"
  puts "-W: Update apache proxy entry for AI"
  puts "-R: Use alternate package repository (additional packages like puppet)"
  puts "-Z: Destroy ZFS filesystem as part of uninstallation"
  puts "-D: Use default values for questions"
  puts ""
  puts "Server related examples:"
  puts ""
  puts "List AI services:\t\t"+$script+" -A -S -L"
  puts "List KS services:\t\t"+$script+" -K -S -L"
  puts "Configure all AI services:\t"+$script+" -A -S"
  puts "Configure KS services:\t\t"+$script+" -K -S"
  puts "Unconfigure AI service:\t\t"+$script+" -A -S -z sol_11_1"
  puts "Unconfigure KS service:\t\t"+$script+" -K -S -z rh_5_9"
  puts
  puts "Maintenance related examples:"
  puts
  puts "Configure AI client services:\t"+$script+" -A -M -C -a i386"
  puts "Enable AI proxy:\t\t"+$script+" -A -M -W -n sol_11_1"
  puts "Disable AI proxy:\t\t"+$script+" -A -M -W -z sol_11_1"
  puts "Configure AI alternate repo:\t"+$script+" -A -M -R"
  puts "Unconfigure AI alternate repo:\t"+$script+" -A -M -R -z sol_11_1_alt"
  puts "Configure KS alternate repo:\t"+$script+" -K -M -R -n centos_5_9"
  puts "Unconfigure KS alternate repo:\t"+$script+" -K -M -R -z centos_5_9"
  puts "Enable KS alias:\t\t"+$script+" -K -M -W -n centos_5_9"
  puts "Disable KS alias:\t\t"+$script+" -K -M -W -z centos_5_9"
  puts "Import KS PXE files:\t\t"+$script+" -K -M -P -n centos_5_9"
  puts "Delete $KS PXE files:\t\t"+$script+" -K -M -P -z centos_5_9"
  puts "Unconfigure KS client PXE:\t"+$script+" -K -M -P -d centos59vm01"
  puts
  puts "Client related examples:"
  puts
  puts "List AI clients:\t\t"+$script+" -A -C -L"
  puts "List KS clients:\t\t"+$script+" -K -C -L"
  puts "Create AI client:\t\t"+$script+" -A -C -c sol11u01vm03 -e 00:50:56:26:92:d8 -a i386 -i 192.168.1.193"
  puts "Delete AI client:\t\t"+$script+" -A -C -d sol11u01vm03"
  puts "Create KS client:\t\t"+$script+" -K -C -c centos59vm01 -e 00:50:56:34:4E:7A -i 192.168.1.194 -n centos_5_9"
  puts "Delete KS client:\t\t"+$script+" -K -C -d centos59vm01"
  puts "Configure KS client PXE:\t"+$script+" -K -P -c centos59vm01 -e 00:50:56:34:4E:7A -i 192.168.1.194 -n centos_5_9"
  puts
  exit
end

# Get version

def get_version()
  file_array=IO.readlines $0
  version=file_array.grep(/^# Version/)[0].split(":")[1].gsub(/^\s+/,'').chomp
  packager=file_array.grep(/^# Packager/)[0].split(":")[1].gsub(/^\s+/,'').chomp
  name=file_array.grep(/^# Name/)[0].split(":")[1].gsub(/^\s+/,'').chomp
  return version
end

# Print script version information

def print_version()
  version=get_version()
  puts name+" v. "+version+" "+packager
  exit
end

# Check local configuration
# Create work directory if it doesn't exist
# If not running on Solaris, run in test mode
# Useful for generating client config files

def check_local_config()
  if !$work_dir.match(/[A-z]/)
    dir_name=File.basename($script,".*")
    id=%x[/usr/bin/id -u]
    id=Integer(id)
    if id == 0
      $work_dir="/opt/"+dir_name
    else
      $work_dir=$home_dir+"/."+dir_name
    end
  end
  if $verbose_mode == 1
    puts "Information:\tSetting work directory to "+$work_dir
  end
  check_dir_exists($work_dir)
  if !$tmp_dir.match(/[A-z]/)
    $tmp_dir=$work_dir+"/tmp"
  end
  if $verbose_mode == 1
    puts "Information:\tSetting temporary directory to "+$work_dir
  end
  check_dir_exists($tmp_dir)
  os_name=%x["uname"]
  if !os_name.match(/SunOS/)
    $test_mode=1
  else
    os_ver=%x[uname -r]
    if os_ver.match(/5\.11/)
      $default_net="net0"
    end
  end
  if !$default_host.match(/[0-9]/)
    message="Determining:\tDefault host IP"
    command="ipadm show-addr #{$default_net}/v4 |grep net |awk '{print $4}' |cut -f1 -d'/'"
    $default_host=execute_command(message,command)
    $default_host=$default_host.chomp
  end
  if !$default_apache_allow.match(/[0-9]/)
    $default_apache_allow=$default_host.split(/\./)[0..2].join(".")
  end
  if $verbose_mode == 1
    puts "Information:\tSetting apache allow range to "+$default_apache_allow
  end
  return
end

# Get command line arguments
# Print help if given none

if !ARGV[0]
  print_usage()
end

begin
  opt=Getopt::Std.getopts($options)
rescue
  print_usage()
end

# Print version

if opt["V"]
  print_version()
  exit
end

# Prient usage

if opt["h"]
  print_usage()
end

# Enable test mode

if opt["v"]
  $verbose_mode=1
  puts "Information:\tRunning in verbose mode"
end

# Enable verbose mode

if opt["t"]
  $test_mode=1
  puts "Information:\tRunning in test mode"
end

# Check local configuration

check_local_config()

if !opt["c"] and !opt["S"] and !opt["d"] and !opt["z"] and !opt["W"] and !opt["C"] and !opt["R"] and !opt["L"] and !opt["P"]
  puts "Warning:\tClient name not given"
  exit
else
  if opt["c"]
    client_name=opt["c"]
  end
  if opt["d"]
    client_name=opt["d"]
  end
  if opt["z"]
    service_name=opt["z"]
  end
  if opt["n"]
    service_name=opt["n"]
  end
  if opt["c"] or opt["d"]
    if $verbose_mode == 1
      puts "Information:\tSetting client name to "+client_name
    end
  end
  if opt["z"] or opt["n"]
    if $verbose_mode == 1
      puts "Information:\tSetting service name to "+service_name
    end
  end
end

# Get MAC address if given

if opt["e"]
  client_mac=opt["e"]
end
if $verbose_mode == 1
   puts "Information:\tClient ethernet MAC address is "+client_mac
end

# Routines for Jumpstart (Solaris 10 and earlier)

if opt["J"]
  if opt["d"]
    client_name=opt["d"]
    delete_js_client(client_name)
  else
    if opt["S"]
      if opt["n"]
        service_name=opt["n"]
      end
    end
  end
end

# Get/set publisher port

if opt["p"]
  publisher_port=opt["p"]
else
  publisher_port=$default_ai_port
end
if $verbose_mode == 1
   puts "Information:\tSetting publisher port to "+publisher_port
end

# Get/set publisher host

if opt["h"]
  publisher_host=opt["h"]
else
  publisher_host=$default_host
end
if $verbose_mode == 1
   puts "Information:\tSetting publisher host to "+publisher_port
end

# Get IP address if given

if opt["i"]
  client_ip=opt["i"]
else
  client_mac=""
end
if $verbose_mode == 1
   puts "Information:\tClient IP address is "+client_ip
end

# Get/set service name

if opt["n"]
  service_name=opt["n"]
  if !service_name.match(/^[A-z]/)
    puts "Warning:\tService name must start with letter"
  end
else
  if !opt["z"]
    service_name=""
  end
end

# Get ISO file if given

if opt["f"]
  iso_file=opt["f"]
  if $verbose_mode == 1
     puts "Information:\tUsing ISO "+iso_file
  end
else
  iso_file=""
end

# Get architecture if given

if opt["a"]
  client_arch=opt["a"]
  client_arch=client_arch.downcase
  if $verbose_mode == 1
     puts "Information:\tSetting architecture to "+client_arch
  end
else
  client_arch=""
end

# If given -Z destroy ZFS filesystems as part of unconfigure

if opt["Z"]
  $destroy_fs=1
  if $verbose_mode == 1
     puts "Warning:\tDestroying ZFS filesystems"+client_arch
  end
end

# If given -R use alternate repos

if opt["R"]
  $use_alt_repo=1
end

# If given -D choose defaults for questions

if opt["D"]
  $use_defaults=1
  if $verbose_mode == 1
    puts "Information:\tSetting answers to defaults"
  end
end

# Handle AI, KS, or JS

if opt["A"] or opt["K"] or opt["J"]
  # Set function
  if opt["A"]
    funct="ai"
  end
  if opt["K"]
    funct="ks"
  end
  if opt["J"]
    funct="js"
  end
  # Handle server related functions
  if opt ["S"]
    # List server services
    if opt["L"]
      eval"[list_#{funct}_services()]"
      exit
    end
    # Unconfigure server services
    if opt["z"]
      eval"[unconfigure_#{funct}_services(service_name)]"
      exit
    end
    eval"[configure_#{funct}_server(client_arch,publisher_host,publisher_port,service_name,iso_file)]"
    exit
  end
  # Handle client related services
  if opt["d"]
    eval"[unconfigure_#{funct}_client(client_name,client_mac,service_name)]"
    exit
  end
  # Perform maintenance related functions
  if opt["M"]
    # Handle PXE services
    if opt["P"]
      if opt["d"]
        eval"[unconfigure_#{funct}_pxeclient(client_name)]"
      end
      if opt["z"]
        eval"[unconfigure_#{funct}_pxeboot(service_name)]"
      end
      if opt["n"]
        eval"[configure_#{funct}_pxeboot(service_name)]"
      end
      exit
    end
    # Handle web services
    if opt["W"]
      eval"[add_#{funct}_service(service_name)]"
      if opt["n"]
        eval"[add_#{funct}_apache(service_name)]"
      else
        eval"[remove_#{funct}_apache(service_name)]"
      end
      exit
    end
    if opt["C"]
      eval"[configure_#{funct}_client_services(client_arch,publisher_host,publisher_port,service_name)]"
      exit
    end
    # Handle alternate packages (non OS install related)
    if opt["R"]
      if opt["z"]
        eval"[unconfigure_#{funct}_alt_repo()]"
      else
        eval"[configure_#{funct}_alt_repo()]"
      end
      exit
    end
  end
  # Perform client related functions
  if opt["C"]
      # List clients
    if opt["L"]
      eval"[list_#{funct}_clients()]"
      exit
    end
    if opt["c"]
      if !opt["K"]
        check_client_arch(client_arch)
      end
      check_client_mac(client_mac)
      check_client_arch(client_arch)
      check_client_ip(client_ip)
      eval"[configure_#{funct}_client(client_name,client_arch,client_arch,client_ip)]"
    end
  end
end
