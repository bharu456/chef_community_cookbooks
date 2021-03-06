#
# Cookbook Name:: nagios3
# Recipe:: nagios_client
#
# Copyright 2015, DennyZhang.com
#
# Apache License, Version 2.0
#

case node['platform_family']
when 'debian'
  ['nagios-nrpe-server', 'nagios-plugins', \
   'nagios-plugins-basic', 'libsys-statistics-linux-perl'].each do |x|
    apt_package x do
      action :install
      not_if "dpkg -l #{x} | grep -E '^ii'"
    end
  end

  # install nagios-nrpe-plugin will install and start apache2, which is not expected
  # In nagios server
  if !node['nagios3']['server_ip'].index(node['ipaddress']).nil? || \
     !node['nagios3']['server_ip'].index(node['hostname']).nil? || \
     !node['nagios3']['server_ip'].index('localhost').nil? || \
     !node['nagios3']['server_ip'].index('127.0.0.1').nil?
    apt_package 'nagios-nrpe-plugin' do
      action :install
      not_if "dpkg -l nagios-nrpe-plugin | grep -E '^ii'"
    end
  else
    # in pure nagios client
    service node['nagios3']['apache_name'] do
      action [:stop, :disable]
    end

    apt_package 'nagios-nrpe-plugin' do
      action :install
      notifies :stop, "service[#{node['nagios3']['apache_name']}]", :immediately
      not_if "dpkg -l nagios-nrpe-plugin | grep -E '^ii'"
    end
  end
when 'fedora', 'rhel', 'suse'
  %w(nagios-plugins-nrpe nagios-plugins-all nrpe perl-Sys-Statistics-Linux).each do |x|
    yum_package x do
      action :install
    end
  end
else
  Chef::Application.fatal!("Need to customize for OS of #{node['platform_family']}")
end

# Make sure nagios user to run admin commands like lsof without problem
file '/etc/sudoers.d/nagios' do
  mode '0440'
  content '%nagios ALL=(ALL:ALL) NOPASSWD: ALL'
end

###################### Install Basic Files for Checks #####################
remote_directory '/etc/nagios/log_cfg' do
  files_mode '0755'
  files_owner 'root'
  mode '0755'
  owner 'root'
  source 'log_cfg'
end
###########################################################################

######################## nagios check plugins ##########################
directory '/etc/nagios/nrpe.d' do
  owner 'root'
  group 'root'
  mode 0o755
  recursive true
  action :create
end

allowed_hosts = node['nagios3']['allowed_hosts']

if node['nagios3']['allowed_hosts'].index(node['nagios3']['server_ip']).nil?
  allowed_hosts = if allowed_hosts == ''
                    node['nagios3']['server_ip']
                  else
                    allowed_hosts + ',' + node['nagios3']['server_ip']
                  end
end

template '/etc/nagios/nrpe.cfg' do
  source 'nrpe.cfg.erb'
  owner 'root'
  group 'root'
  mode 0o755
  variables(
    allowed_hosts: allowed_hosts
  )
  notifies :restart, "service[#{node['nagios3']['nrpe_name']}]", :delayed
end

template '/etc/nagios/nrpe.d/common_nrpe.cfg' do
  source 'common_nrpe.cfg.erb'
  owner 'root'
  group 'root'
  mode 0o755
  variables(
    nagios_plugins: node['nagios3']['plugins_dir']
  )
  notifies :restart, "service[#{node['nagios3']['nrpe_name']}]", :delayed
end

template '/etc/nagios/nrpe.d/my_nrpe.cfg' do
  source 'my_nrpe.cfg.erb'
  owner 'root'
  group 'root'
  mode 0o755
  variables(
    apache_pid_file: node['nagios3']['apache_pid_file'],
    nagios_plugins: node['nagios3']['plugins_dir']
  )
  notifies :restart, "service[#{node['nagios3']['nrpe_name']}]", :delayed
end

template '/etc/nagios/nrpe.d/check_logfile.cfg' do
  source 'check_logfile.cfg.erb'
  owner 'root'
  group 'root'
  mode 0o755
  variables(
    nagios_plugins: node['nagios3']['plugins_dir']
  )
  notifies :restart, "service[#{node['nagios3']['nrpe_name']}]", :delayed
end

directory node['nagios3']['plugins_dir'] do
  owner 'root'
  group 'root'
  mode 0o755
  recursive true
  action :create
end

# TODO: change this later
# specify file checksum to avoid external network request
download_prefix = 'https://raw.githubusercontent.com/DennyZhang/devops_public/tag_v4'

nagios_plugin_list = \
  ['check_proc_mem.sh:c451946d6c8334d384f8fa70cc9ded329717e726146c385b8610824e6b746052',
   'check_proc_cpu.sh:f874bd1721c38cb191b84998a4feded999ba6830f18e7aa1771ebdc1c398adab',
   'check_proc_fd.sh:fb2e8b19094d5b6c609b03fc2c93054b6a213b9074fa9305b71673a36588451c',
   'check_proc_threadcount.sh:3ebbba5c577968d3aa909d98fcc4b545d2c1c6a2789ddff77938b6da2f347079',
   'check_out_of_memory.py:70a7eb0dc13cac431eeb943db2fcb5e429dc4d02dccadd93451809573e5c61b2']

nagios_plugin_list.each do |plugin|
  l = plugin.split(':')
  plugin = l[0]
  plugin_name = plugin.split('.')[0]
  file_checksum = l[1]

  remote_file "#{node['nagios3']['plugins_dir']}/#{plugin}" do
    source "#{download_prefix}/nagios_plugins/#{plugin_name}/#{plugin}"
    owner 'nagios'
    group 'nagios'
    mode '0755'
    checksum file_checksum
    retries 3
    retry_delay 3
  end
end

%w(check_linux_stats.pl check_ip_address.sh).each do |x|
  template "#{node['nagios3']['plugins_dir']}/#{x}" do
    source "#{x}.erb"
    owner 'root'
    group 'root'
    mode 0o755
  end
end

# ######################### selenium_test ################################
# remote_file '/opt/selenium-server-standalone-2.38.0.jar' do
# source 'https://selenium.googlecode.com/files/selenium-server-standalone-2.38.0.jar'
# use_last_modified true
# mode '0755'
# action :create_if_missing
# end

########################################################################
# Install plugin
%w(check_logfiles check_service_status.sh).each do |x|
  cookbook_file "#{node['nagios3']['plugins_dir']}/#{x}" do
    source x
    mode '0755'
  end
end

service node['nagios3']['nrpe_name'] do
  supports status: true, restart: true, reload: true
  action [:enable, :start]
end

user 'nagios' do
  shell '/bin/bash'
end
