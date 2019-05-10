################################################################################
#
# Copyright 2017 Centrify Corporation
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

$TEMP_DEPLOY_DIR='/tmp/auto_centrify_deployment/centrifydc'
local_keytab=$TEMP_DEPLOY_DIR+"/login.keytab"
$CENTRIFY_REPO_CREDENTIAL=''

$CENTRIFYDC_JOIN_TO_AD='no'
$CENTRIFYDC_ZONE_NAME=''
$CENTRIFYDC_ADDITIONAL_PACKAGES=''
$CENTRIFYDC_KEYTAB_S3_BUCKET = ''
$CENTRIFYDC_ADJOIN_ADDITIONAL_OPTIONS = ''
$s3_bucket_region = ''
$centrifydc_pkgs=''
$krb5_cache_lifetime='10m'

case node[:platform] 
  when 'redhat','centos','amazon','ubuntu'
    nil
  else
    raise "Not support current os: #{node[:platform]}"
end

### Check attributes ###
check_dc_attr = ['CENTRIFYDC_JOIN_TO_AD', 'CENTRIFYDC_ZONE_NAME', 'CENTRIFY_REPO_CREDENTIAL', 'CENTRIFYDC_ADDITIONAL_PACKAGES', 'CENTRIFYDC_KEYTAB_S3_BUCKET']
# Must be a type of String 
check_dc_attr.each do |attr|
  if node[attr].class != String
    raise "#{attr} must be a string type!"
  end
end

$CENTRIFYDC_JOIN_TO_AD = node['CENTRIFYDC_JOIN_TO_AD']
if !(["yes", "no"].include? node['CENTRIFYDC_JOIN_TO_AD'])
  raise 'Must set CENTRIFYDC_JOIN_TO_AD to yes or no'
end

$CENTRIFY_REPO_CREDENTIAL = node['CENTRIFY_REPO_CREDENTIAL']
if $CENTRIFY_REPO_CREDENTIAL.empty?
  raise "Can't find any valid definition of the CENTRIFY_REPO_CREDENTIAL attribute"
end

# Check CENTRIFYDC_ADDITIONAL_PACKAGES
if !node['CENTRIFYDC_ADDITIONAL_PACKAGES'].empty?
  $CENTRIFYDC_ADDITIONAL_PACKAGES = node['CENTRIFYDC_ADDITIONAL_PACKAGES'].downcase
  # All packages must be valid centrify packages
  $CENTRIFYDC_ADDITIONAL_PACKAGES = `echo -n "#{$CENTRIFYDC_ADDITIONAL_PACKAGES}" | awk '{for(i=1;i<=NF;i++){ print $i;}}' | sort | uniq | awk '{printf("%s ", $1)}' |  awk 'BEGIN {invlid=0} {if(invalid != 1) {for(i=1;i<=NF;i++){if($i != "centrifydc-ldapproxy" && $i != "centrifydc-openssh" && $i != "") {invalid=1;printf("invalid ");break};if ( i == 1) { printf("%s", $i)} else { printf(" %s", $i)}} }}'`
  if ($CENTRIFYDC_ADDITIONAL_PACKAGES.empty?) || ($CENTRIFYDC_ADDITIONAL_PACKAGES.include? "invalid")
    raise 'Invalid CENTRIFYDC_ADDITIONAL_PACKAGES attribute!'
  end
end
case node[:platform]
when 'redhat','centos','amazon'
  $centrifydc_pkgs = "CentrifyDC " + $CENTRIFYDC_ADDITIONAL_PACKAGES.gsub(/centrifydc/,'CentrifyDC')
else
  $centrifydc_pkgs = "centrifydc " + $CENTRIFYDC_ADDITIONAL_PACKAGES
end
$centrifydc_pkgs = $centrifydc_pkgs.split(/\s+/)

if $CENTRIFYDC_JOIN_TO_AD == 'yes'
  $CENTRIFYDC_ZONE_NAME = node['CENTRIFYDC_ZONE_NAME']
  if $CENTRIFYDC_ZONE_NAME.empty?
    raise "CENTRIFYDC_ZONE_NAME can't be empty string!"
  end
  $CENTRIFYDC_ADJOIN_ADDITIONAL_OPTIONS = node['CENTRIFYDC_ADJOIN_ADDITIONAL_OPTIONS']
end

adjoined = system('/usr/bin/adinfo')
if $CENTRIFYDC_JOIN_TO_AD == 'yes' || adjoined
  $CENTRIFYDC_KEYTAB_S3_BUCKET = node['CENTRIFYDC_KEYTAB_S3_BUCKET']
end

### Start to deploy ###
if $CENTRIFYDC_JOIN_TO_AD == 'yes' || adjoined
  directory "delete_deploy_dir" do
    path $TEMP_DEPLOY_DIR
    recursive true
    action :delete
  end
  directory "create_deploy_dir" do
    path $TEMP_DEPLOY_DIR
    owner 'root'
    group 'root'
    mode '0700'
    recursive true
    action :create
  end
  # Create login.keytab from s3 bucket or cookbook files
  if $CENTRIFYDC_KEYTAB_S3_BUCKET != "" 
    chef_gem "aws-sdk" do
      compile_time true
      action :install
    end
    require 'aws-sdk'
    stack = search("aws_opsworks_stack").first
    $s3_bucket_region = stack['region']
    if $s3_bucket_region.nil?
      raise 'Cannot retrieve aws stack region'
    end
    ruby_block "download-object" do
      block do
        s3 = Aws::S3::Client.new(region: $s3_bucket_region)
	if local_keytab.class != String || local_keytab.empty?
	  raise 'No local_keytab definition'
        end
        keytab = s3.get_object(bucket: $CENTRIFYDC_KEYTAB_S3_BUCKET, key: "login.keytab", response_target: local_keytab)
      end
      action :run
    end 
  else
    cookbook_file "#{$TEMP_DEPLOY_DIR}/login.keytab" do
      source 'login.keytab'
      owner 'root'
      group 'root'
      mode  '0400'
      action :create
    end
  end
end 

if adjoined
  bash 'init_krb5_cred_cache_for_adleave' do
    code <<-EOH
    set -x
    [ ! -e /etc/krb5.conf.centrify_backup ] && [ -e /etc/krb5.conf ] && mv /etc/krb5.conf /etc/krb5.conf.centrify_backup
    rm -rf /etc/krb5.conf
    login_keytab=#{local_keytab}
    join_user=`/usr/share/centrifydc/kerberos/bin/klist -k $login_keytab | grep @ | awk '{print $2}' | sed -n '1p' | tr  -d '\n' `
    /usr/share/centrifydc/kerberos/bin/kinit -kt  $login_keytab -l #{$krb5_cache_lifetime} $join_user
    EOH
    only_if 'test -x /usr/share/centrifydc/kerberos/bin/kinit'
    timeout 5
  end

  bash 'ensure_not_adjoined' do
    code <<-EOH
      set -x
      adleave -r 
      exit $?
    EOH
    timeout 20
  end
end


# Centrify repo
bash 'generate_repo' do
  case node[:platform]
  when 'redhat','centos','amazon'
    code <<-EOH
      set -x
      cat >/etc/yum.repos.d/centrify.repo <<END
[centrify]
name=centrify
baseurl=https://#{$CENTRIFY_REPO_CREDENTIAL}@repo.centrify.com/rpm-redhat/
enabled=1
repo_gpgcheck=1
gpgcheck=1
gpgkey=https://edge.centrify.com/products/RPM-GPG-KEY-centrify 
END
    rm -rf /var/cache/yum/*
    yum -y clean all
    yum repolist -y
    EOH
  when 'ubuntu'
    code <<-EOH
      set -x
      bash -c 'wget -O - https://edge.centrify.com/products/RPM-GPG-KEY-centrify | apt-key add -'
      [ ! -f /etc/dpkg/dpkg.cfg.centrify_backup ] && cp /etc/dpkg/dpkg.cfg /etc/dpkg/dpkg.cfg.centrify_backup
      if grep -E "^[[:space:]]*no-debsig" /etc/dpkg/dpkg.cfg ;then
        sed -i -r 's/^[[:space:]]*no-debsig[[:space:]]*$/#no-debsig/' /etc/dpkg/dpkg.cfg
        [ $? -ne 0 ] && exit 1
      fi
      src_repo="deb https://#{$CENTRIFY_REPO_CREDENTIAL}@repo.centrify.com/deb stable main" 
      if grep '@repo.centrify.com/deb stable main' /etc/apt/sources.list; then
        sed -i "/@repo\.centrify\.com\\/deb stable main/d" /etc/apt/sources.list
        [ $? -ne 0 ] && exit 1
      fi
      echo "$src_repo" >> /etc/apt/sources.list
      apt-get -y clean
      apt-get -y update
    EOH
  end
  timeout 60
end

$centrifydc_pkgs.each do |centrify_pkg|
  package centrify_pkg do
    case node[:platform]
    when 'redhat', 'centos', 'amazon'
      flush_cache({:before => true, :after => true})
    end
    timeout 120
    options "-y"
  end
end

# Configure centrify.conf to support SSO
bash 'configure_centrifydc' do
  code <<-EOH
    set -x
    sed  -i -r '/^[[:space:]]*adclient.dynamic.dns.enabled[[:space:]]*:.*$/d' /etc/centrifydc/centrifydc.conf
    echo "adclient.dynamic.dns.enabled: true" >> /etc/centrifydc/centrifydc.conf
    sed -i -r '/^[[:space:]]*krb5.forwardable.user.tickets[[:space:]]*:.*$/d' /etc/centrifydc/centrifydc.conf
    echo "krb5.forwardable.user.tickets: true" >> /etc/centrifydc/centrifydc.conf
  EOH
  timeout 5
end

 # Adjoin to domain and zone
if $CENTRIFYDC_JOIN_TO_AD == 'yes'
  bash 'init_krb5_cred_cache_for_adjoin' do
    code <<-EOH
      set -x
      [ ! -e /etc/krb5.conf.centrify_backup ] && [ -e /etc/krb5.conf ] && mv /etc/krb5.conf /etc/krb5.conf.centrify_backup
      rm -rf /etc/krb5.conf
      login_keytab=#{local_keytab}
      join_user=`/usr/share/centrifydc/kerberos/bin/klist -k $login_keytab | grep @ | awk '{print $2}' | sed -n '1p' | tr  -d '\n' `
      /usr/share/centrifydc/kerberos/bin/kinit -kt  $login_keytab -l #{$krb5_cache_lifetime} $join_user
    EOH
    timeout 5
  end
  bash 'join_domain' do
    code <<-EOH
      set -x
      PATH=$PATH:/usr/sbin/
      login_keytab=#{local_keytab}
      domain_name=`/usr/share/centrifydc/kerberos/bin/klist -k $login_keytab | grep '@' | cut -d '@' -f 2 | sed -n '1p' | tr -d '\n' `
      adlicense -l
      adjoin $domain_name -z #{$CENTRIFYDC_ZONE_NAME} --name `hostname` #{$CENTRIFYDC_ADJOIN_ADDITIONAL_OPTIONS}
      r=$?
	  rm $login_keytab
      [ $r -ne 0 ] && echo "adjoin failed!" && exit $r
      adinfo | grep 'CentrifyDC mode' | grep 'connected' >/dev/null
      [ $? -ne 0 ] && echo "adjoin failed because it doesn't enable license" && exit 1
      adinfo | grep 'CentrifyDC mode' | grep 'connected' >/dev/null
      [ $? -ne 0 ] && echo "adjoin failed because it can't connect to adclient" && exit 1
      /usr/share/centrifydc/kerberos/bin/kdestroy
      exit 0
    EOH
    timeout 20
  end
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

