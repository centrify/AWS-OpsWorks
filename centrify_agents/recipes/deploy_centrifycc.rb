################################################################################
#
# Copyright 2021 Centrify Corporation
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#    http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
################################################################################

$TEMP_DEPLOY_DIR = '/tmp/auto_centrify_deployment'
$CENTRIFYCC_DOWNLOAD_PREFIX='https://downloads.centrify.com/products/cloud-service/CliDownload/Centrify'
$CENTRIFYCC_RPM_NAME=''

$CENTRIFYCC_TENANT_URL = ''
$CENTRIFYCC_ENROLLMENT_CODE = ''
$CENTRIFYCC_AGENT_AUTH_ROLES = ''
$CENTRIFYCC_FEATURES = ''
$CENTRIFYCC_NETWORK_ADDR_TYPE = ''
$CENTRIFYCC_COMPUTER_NAME_PREFIX = ''
$CENTRIFYCC_CENROLL_ADDITIONAL_OPTIONS = ''
$CENTRIFYCC_AGENT_SETS = ''
$network_addr = ''
$ec2_instance_id = ''

all_attribute = ["CENTRIFYCC_TENANT_URL","CENTRIFYCC_ENROLLMENT_CODE","CENTRIFYCC_AGENT_AUTH_ROLES","CENTRIFYCC_FEATURES","CENTRIFYCC_NETWORK_ADDR_TYPE","CENTRIFYCC_COMPUTER_NAME_PREFIX", "CENTRIFYCC_AGENT_SETS"]

### Check attributes ###
check_cc_attr = ["CENTRIFYCC_TENANT_URL", "CENTRIFYCC_ENROLLMENT_CODE", "CENTRIFYCC_FEATURES", "CENTRIFYCC_NETWORK_ADDR_TYPE", "CENTRIFYCC_COMPUTER_NAME_PREFIX"]
check_cc_attr.each do |attr|
  if node[attr].class != String
    raise "#{attr} must be a string type!"
  end
end
if node['CENTRIFYCC_TENANT_URL'].empty?
  raise 'CENTRIFYCC_TENANT_URL cannot be empty'
end
$CENTRIFYCC_TENANT_URL = node['CENTRIFYCC_TENANT_URL']
if node['CENTRIFYCC_ENROLLMENT_CODE'].empty?
  raise 'CENTRIFYCC_ENROLLMENT_CODE cannot be empty'
end
$CENTRIFYCC_ENROLLMENT_CODE = node['CENTRIFYCC_ENROLLMENT_CODE']

$CENTRIFYCC_AGENT_SETS = ''
if !node['CENTRIFYCC_AGENT_SETS'].nil?
  if !node['CENTRIFYCC_AGENT_SETS'].empty? 
    if node['CENTRIFYCC_AGENT_SETS'].class != String
      raise "CENTRIFYCC_AGENT_SETS must be a string type!"
    else
      $CENTRIFYCC_AGENT_SETS = node['CENTRIFYCC_AGENT_SETS']
    end
  end
end

$CENTRIFYCC_AGENT_AUTH_ROLES = ''
if !node['CENTRIFYCC_AGENT_AUTH_ROLES'].nil?
  if !node['CENTRIFYCC_AGENT_AUTH_ROLES'].empty? 
    if node['CENTRIFYCC_AGENT_AUTH_ROLES'].class != String
      raise "CENTRIFYCC_AGENT_AUTH_ROLES must be a string type!"
    else
      $CENTRIFYCC_AGENT_AUTH_ROLES = node['CENTRIFYCC_AGENT_AUTH_ROLES']
    end
  end
end

if $CENTRIFYCC_AGENT_SETS == '' && $CENTRIFYCC_AGENT_AUTH_ROLES == '' 
  raise 'CENTRIFYCC_AGENT_AUTH_ROLES and CENTRIFYCC_AGENT_SETS cannot both be empty'
end

puts "CENTRIFYCC_AGENT_SETS: #{$CENTRIFYCC_AGENT_SETS}"
puts "CENTRIFYCC_AGENT_AUTH_ROLES: #{$CENTRIFYCC_AGENT_AUTH_ROLES}"

if node['CENTRIFYCC_FEATURES'].empty?
  raise 'CENTRIFYCC_FEATURES cannot be empty'
end
$CENTRIFYCC_FEATURES = node['CENTRIFYCC_FEATURES'] 
if node['CENTRIFYCC_NETWORK_ADDR_TYPE'].empty?
  raise 'CENTRIFYCC_NETWORK_ADDR_TYPE cannot be empty'
end
$CENTRIFYCC_NETWORK_ADDR_TYPE = node['CENTRIFYCC_NETWORK_ADDR_TYPE']
$CENTRIFYCC_CENROLL_ADDITIONAL_OPTIONS = node['CENTRIFYCC_CENROLL_ADDITIONAL_OPTIONS']
instance = search("aws_opsworks_instance", "self:true").first
if instance.nil? || instance['instance_id'].nil? || instance['instance_id'].empty?
   raise "Can't retrieve aws instance id"
end
$ec2_instance_id = instance['instance_id']

# set up hostname
$host_name = `hostname --fqdn`
if $host_name.nil? || $host_name.empty?
  $host_name = `hostname`
end
if $host_name.nil? || $host_name.empty?
  raise "Can't retrieve host name"
end
# remove .localdomain from hostname
$host_name.chomp!
$host_name.chomp!(".localdomain")
	
case $CENTRIFYCC_NETWORK_ADDR_TYPE
  when 'PublicIP'
    $public_ip = instance['public_ip']
    if $public_ip.nil? || $public_ip.empty?
      raise "Can't retrieve public ip for CENTRIFYCC_NETWORK_ADDR_TYPE"
    else
      $network_addr = $public_ip
    end
  when 'PrivateIP'
    $private_ip = instance['private_ip']
    if $private_ip.nil? || $private_ip.empty?
      raise "Can't retrieve private ip for CENTRIFYCC_NETWORK_ADDR_TYPE"
    else
      $network_addr = $private_ip
    end
  when 'HostName'
      $network_addr = $host_name
  else
    raise "Invalid CENTRIFYCC_NETWORK_ADDR_TYPE: #{$CENTRIFYCC_NETWORK_ADDR_TYPE}"
end
      
if node['CENTRIFYCC_COMPUTER_NAME_PREFIX'].empty?
   $CENTRIFYCC_COMPUTER_NAME_PREFIX = ""
   computer_name = $host_name 
 else
   $CENTRIFYCC_COMPUTER_NAME_PREFIX = node['CENTRIFYCC_COMPUTER_NAME_PREFIX']
   computer_name = "#{$CENTRIFYCC_COMPUTER_NAME_PREFIX}-#{$host_name}"
end
bash 'ensure_not_cenrolled' do
  code <<-EOH
    set -x
    cunenroll -m -d 
  EOH
  timeout 20
  only_if 'which cinfo && cinfo'
end

bash 'ensure_necessary_tools' do
  code <<-EOH
    set -x
    case #{node[:platform]} in
      redhat|centos|amazon)
        yum install selinux-policy-targeted -y
        [ $? -ne 0 ] && echo "yum install selinux-policy-targeted failed!" && exit 1
        yum install perl -y
        [ $? -ne 0 ] && echo "yum install perl failed!" && exit 1
      ;;
    esac
    exit 0
  EOH
  timeout 60
end

# resolve rpm name
case node[:platform]
when "redhat", "amazon", "centos"
  $CENTRIFYCC_RPM_NAME="CentrifyCC-rhel6.x86_64.rpm"
when "ubuntu"
  $CENTRIFYCC_RPM_NAME="centrifycc-deb9-x86_64.deb"
else
   raise "Cannot resolve rpm package name for centrifycc on current OS #{node[:platform]}"
end      

# download and install rpm
bash 'download and install rpm' do
  code <<-EOH
    set -x
    download_url="#{$CENTRIFYCC_DOWNLOAD_PREFIX}/#{$CENTRIFYCC_RPM_NAME}"
    download_dir=/tmp
    curl --fail -o $download_dir/#{$CENTRIFYCC_RPM_NAME} $download_url
    r=$?
    if [ $r -ne 0 ];then
        echo "Download the rpm package #{$CENTRIFYCC_RPM_NAME} unsuccessfully"
        exit $r
    fi
        
    case "#{node[:platform]}" in
    redhat|amazon|centos)
      package_name=`echo #{$CENTRIFYCC_RPM_NAME} | cut -d '-' -f 1`
      rpm -q $package_name
      if [ $? -eq 0 ];then
          rpm -e $package_name
          r=$?
          if [ $r -ne 0 ];then
              echo "Remove rpm $package_name unsuccessfully"
              exit $r
          fi
      fi

      rpm -ivh $download_dir/#{$CENTRIFYCC_RPM_NAME}
      r=$?
      if [ $r -ne 0 ];then
          echo "Install the rpm package #{$CENTRIFYCC_RPM_NAME} unsuccessfully"
          exit $r
      fi
      ;;
    ubuntu)
      package_name=`echo #{$CENTRIFYCC_RPM_NAME} | cut -d '-' -f 1`
      dpkg -l $package_name
      if [ $? -eq 0 ];then
          dpkg -r $package_name
          r=$?
          if [ $r -ne 0 ];then
              echo "Remove rpm $package_name unsuccessfully"
              exit $r
          fi
      fi
          
      dpkg -i $download_dir/#{$CENTRIFYCC_RPM_NAME}
      r=$?
      if [ $r -ne 0 ];then
        echo "Install the rpm package #{$CENTRIFYCC_RPM_NAME} unsuccessfully"
          exit $r
        fi
        ;;
    *)
      echo "Doesn't support installing the package #{$CENTRIFYCC_RPM_NAME} on the OS $OS_NAME currently"
      r=1
      ;;
    esac
    rm -rf $download_dir/#{$CENTRIFYCC_RPM_NAME}
    exit $r
  EOH
  timeout 120
end
   
bash 'enable_sshd_password_auth' do
  code <<-EOH
    set -x
    need_config_ssh=''
    if test -x /usr/share/centrifydc/sbin/sshd ;then
      if grep -E '^PasswordAuthentication[[:space:]][[:space:]]*no[[:space:]]*$' /etc/centrifydc/ssh/sshd_config >/dev/null ; then
        need_config_ssh='centrifydc'
        src_conf=/etc/centrifydc/ssh/sshd_config
        backup_conf=/etc/centrifydc/ssh/sshd_config.deploy_backup
      fi
    else
      if grep -E '^PasswordAuthentication[[:space:]][[:space:]]*no[[:space:]]*$' /etc/ssh/sshd_config >/dev/null ; then
        need_config_ssh='stock'
        src_conf=/etc/ssh/sshd_config
        backup_conf=/etc/ssh/sshd_config.centrify_backup
      fi
    fi
    r=0
    if [ "x$need_config_ssh" != "x" ];then
      [ ! -f $backup_conf ] && cp $src_conf $backup_conf
      /bin/sed -i -r 's/^PasswordAuthentication[[:space:]][[:space:]]*no[[:space:]]*$/#PasswordAuthentication no/g' $src_conf
      [ $? -ne 0 ] && echo "Comment PasswordAuthentication failed!" && exit 1
      r=1
      case "#{node[:platform]}" in
        ubuntu)
          if [ "$need_config_ssh" = "centrifydc" ];then
            service centrify-sshd restart 
          else
            service ssh restart
          fi
          r=$?
          ;;
        *)
          if [ "$need_config_ssh" = "centrifydc" ];then
            sshd_name=centrify-sshd
          else
            sshd_name=sshd
          fi
          if [ -x /usr/bin/systemctl ]; then
            systemctl restart $sshd_name.service
          else
            /etc/init.d/$sshd_name restart
          fi
          r=$?
          ;;
      esac
      exit $r
    fi
    exit 0
  EOH
  timeout 10
end

bash 'enable_sshd_challenge_response_auth' do
  code <<-EOH
    set -x
    need_config_ssh=''
    if test -x /usr/share/centrifydc/sbin/sshd ;then
      if grep -E '^ChallengeResponseAuthentication[[:space:]][[:space:]]*no[[:space:]]*$' /etc/centrifydc/ssh/sshd_config >/dev/null ; then
        need_config_ssh='centrifydc'
        src_conf=/etc/centrifydc/ssh/sshd_config
        backup_conf=/etc/centrifydc/ssh/sshd_config.deploy_backup
      fi
    else
      if grep -E '^ChallengeResponseAuthentication[[:space:]][[:space:]]*no[[:space:]]*$' /etc/ssh/sshd_config >/dev/null ; then
        need_config_ssh='stock'
        src_conf=/etc/ssh/sshd_config
        backup_conf=/etc/ssh/sshd_config.centrify_backup
      fi
    fi
    r=0
    if [ "x$need_config_ssh" != "x" ];then
      [ ! -f $backup_conf ] && cp $src_conf $backup_conf
      /bin/sed -i -r 's/^ChallengeResponseAuthentication[[:space:]][[:space:]]*no[[:space:]]*$/ChallengeResponseAuthentication yes/g' $src_conf
      [ $? -ne 0 ] && echo "Update ChallengeResponseAuthentication failed!" && exit 1
      r=1
      case "#{node[:platform]}" in
        ubuntu)
          if [ "$need_config_ssh" = "centrifydc" ];then
            service centrify-sshd restart 
          else
            service ssh restart
          fi
          r=$?
          ;;
        *)
          if [ "$need_config_ssh" = "centrifydc" ];then
            sshd_name=centrify-sshd
          else
            sshd_name=sshd
          fi
          if [ -x /usr/bin/systemctl ]; then
            systemctl restart $sshd_name.service
          else
            /etc/init.d/$sshd_name restart
          fi
          r=$?
          ;;
      esac
      exit $r
    fi
    exit 0
  EOH
  timeout 10
end

bash 'start_enroll' do
  code <<-EOH
    set -x
	CMDPARAM=()
	AGENT_AUTH_ROLES="#{$CENTRIFYCC_AGENT_AUTH_ROLES}"
	
	if [ "$AGENT_AUTH_ROLES" != "" ] ; then
	  CMDPARAM=("--agentauth" "#{$CENTRIFYCC_AGENT_AUTH_ROLES}")
	  # grant permssion to view
	  IFS=","
	  for role in $AGENT_AUTH_ROLES
	  do
	    CMDPARAM=("${CMDPARAM[@]}" "--resource-permission" "role:$role:View")
	  done
	fi
	
	# set up add to set
	AGENT_SETS="#{$CENTRIFYCC_AGENT_SETS}"
	if [ "$AGENT_SETS" != "" ] ; then 
	   CMDPARAM=("${CMDPARAM[@]}" "--resource-set" "${AGENT_SETS[@]}")
	fi
	
	# for additional options, need to parse into array
	AGENT_OPTIONS="#{$CENTRIFYCC_CENROLL_ADDITIONAL_OPTIONS}"
	if [ "$AGENT_OPTIONS" != "" ] ; then
	  IFS=' ' read -a tempoption <<< "${AGENT_OPTIONS}"
	  CMDPARAM=("${CMDPARAM[@]}" "${tempoption[@]}")
	fi
	
    /usr/share/centrifycc/bin/cdebug on
    /usr/sbin/cenroll --verbose \
        --tenant "#{$CENTRIFYCC_TENANT_URL}" \
        --code "#{$CENTRIFYCC_ENROLLMENT_CODE}" \
        --features "#{$CENTRIFYCC_FEATURES}" \
        --name "#{computer_name}" \
        --address "#{$network_addr}" \
        "${CMDPARAM[@]}"
         
    r=$?
    [ $r -ne 0 ] && echo "cenroll failed!" && exit $r
    /usr/bin/cinfo
    r=$?
    [ $r -ne 0 ] && echo "cinfo failed after cenroll!" && exit $r
    exit 0
  EOH
  timeout 30
end
