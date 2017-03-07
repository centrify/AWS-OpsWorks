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

case node[:platform] 
  when 'redhat','centos','amazon','ubuntu'
    nil
  else
    raise "Not support current os: #{node[:platform]}"
end

$krb5_cache_lifetime='10m'
$TEMP_DEPLOY_DIR='/tmp/auto_centrify_deployment/centrifydc'
$CENTRIFYDC_KEYTAB_S3_BUCKET = ''
$s3_bucket_region = ''
local_keytab=$TEMP_DEPLOY_DIR+"/login.keytab"


if node['CENTRIFYDC_KEYTAB_S3_BUCKET'].class == String && node['CENTRIFYDC_KEYTAB_S3_BUCKET'] != ''
  $CENTRIFYDC_KEYTAB_S3_BUCKET = node['CENTRIFYDC_KEYTAB_S3_BUCKET']
end


##########　cleanup centrifydc #####################################
directory "#{$TEMP_DEPLOY_DIR}" do
  owner 'root'
  group 'root'
  mode '0700'
  action :create
end

# Generate login.keytab from s3 bucket or cookbook files directory
if $CENTRIFYDC_KEYTAB_S3_BUCKET != "" 
  chef_gem "aws-sdk" do
    compile_time true
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
    ignore_failure true
  end
end

bash 'adleave_domain' do
  code <<-EOH
    login_keytab=#{local_keytab}
    join_user=`/usr/share/centrifydc/kerberos/bin/klist -k $login_keytab | grep @ | awk '{print $2}' | sed -n '1p' | tr  -d '\n' `
    /usr/share/centrifydc/kerberos/bin/kinit -kt  $login_keytab -l #{$krb5_cache_lifetime} $join_user
    /usr/sbin/adleave -r 
    rm -rf $login_keytab
  EOH
  timeout 20
  only_if 'test -x /usr/bin/adinfo && /usr/bin/adinfo'
end

bash 'uninstall_centrifydc' do
  code <<-EOH
    r=0
    case #{node[:platform]} in
      redhat|centos|amazon)
        yum erase CentrifyDC -y
        yum list installed | grep 'CentrifyDC\.' >/dev/null
        [ $? -eq 0 ] && r=1
        ;;
      ubuntu)
        apt-get -y remove centrifydc
        apt-get -y clean >/dev/null
        apt-get -y update >/dev/null
        dpkg --get-selections | grep -w install | grep -w centrifydc >/dev/null
        [ $? -eq 0 ] && r=1
        ;;
      *)
        echo "Not supported os : #{node[:platform]}!"
        r=1
        ;;
    esac
    exit $r
  EOH
  timeout 120
  only_if 'test -x /usr/bin/adinfo && /usr/bin/adinfo --version'
end

bash 'recover_krb5_conf' do
  code <<-EOH
    if [ -f /etc/krb5.conf.centrify_backup ];then
      mv /etc/krb5.conf.centrify_backup /etc/krb5.conf
    fi
  EOH
  timeout 5
  only_if 'test -x /usr/bin/adinfo && /usr/bin/adinfo --version'
end

################ anyway cleanup at last #############################
bash 'clean_files' do
  code <<-EOH
    rm -rf #{$TEMP_DEPLOY_DIR}
  EOH
  timeout 5
  only_if { File.exist? $TEMP_DEPLOY_DIR }
end

bash 'cleanup_repo' do
  code <<-EOH
    case #{node[:platform]} in
      redhat|centos|amazon)
        if [ -f /etc/yum.repos.d/centrify.repo ];then
          rm -rf /etc/yum.repos.d/centrify.repo
        fi
        yum clean -y >/dev/null
        ;;
      ubuntu)
        [ -f /etc/dpkg/dpkg.cfg.centrify_backup ] && cp /etc/dpkg/dpkg.cfg.centrify_backup /etc/dpkg/dpkg.cfg
        sed -i "/@repo.centrify.com\\/deb stable main/d" /etc/apt/sources.list
        apt-get -y clean >/dev/null
        apt-get -y update >/dev/null
        ;;
      *)
        echo "Not supported os: #{node[:platform]}"
        exit 1
        ;;
    esac
    exit 0
  EOH
  timeout 60
end
