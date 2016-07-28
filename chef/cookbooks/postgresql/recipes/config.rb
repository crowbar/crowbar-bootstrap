#
# Copyright 2016, SUSE LINUX GmbH
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

template node[:postgresql][:config][:rails] do
  source "database.yml.erb"
  group "crowbar"
  owner "crowbar"
  mode 0644
  variables(
    username:  node[:postgresql][:username],
    password:  node[:postgresql][:password],
    database:  node[:postgresql][:database],
    host:      node[:postgresql][:host],
    port:      node[:postgresql][:port]
  )
end

template node[:postgresql][:config][:pg_hba] do
  source "pg_hba.conf.erb"
  group "postgres"
  owner "postgres"
  mode 0600
  variables(
    database:           node[:postgresql][:database],
    username:           node[:postgresql][:username],
    client_auth_method: node[:postgresql][:config][:client_auth_method],
    host_auth_method:   node[:postgresql][:config][:host_auth_method]
  )
  notifies :restart, "service[postgresql]", :immediately
end unless node[:postgresql][:remote]
