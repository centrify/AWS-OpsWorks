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

$TEMP_DEPLOY_DIR='/tmp/auto_centrify_deployment'
$CENTRIFYCC_RPM_NAME=""

bash 'cunenroll_cloud' do
  code <<-EOH
    /usr/sbin/cunenroll -m -d
  EOH
  timeout 10
  only_if 'test -x /usr/bin/cinfo && /usr/bin/cinfo'
end

# resolve rpm name
case node[:platform]
when "redhat", "amazon", "centos"
  $CENTRIFYCC_RPM_NAME="CentrifyCC"
when "ubuntu"
  $CENTRIFYCC_RPM_NAME="centrifycc"
else
   raise "Cannot resolve rpm package name for centrifycc on current OS #{node[:platform]}"
end      

bash 'uninstall_centrifycc' do
  code <<-EOH
    r=0
    case #{node[:platform]} in
      redhat|centos|amazon)
        rpm -q #{$CENTRIFYCC_RPM_NAME}
        if [ $? -eq 0 ];then
            rpm -e #{$CENTRIFYCC_RPM_NAME}
            r=$?
        fi
        ;;
      ubuntu)
        dpkg -l #{$CENTRIFYCC_RPM_NAME}
        if [ $? -eq 0 ];then
            dpkg -r #{$CENTRIFYCC_RPM_NAME}
            r=$?
        fi
        ;;
      *)
        echo "Not supported os : #{node[:platform]}!"
        r=1
        ;;
    esac
    exit $r
  EOH
  timeout 60
end
