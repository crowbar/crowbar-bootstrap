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

include_recipe "postgresql::config"

case node[:platform_family]
when "suse"
  package "postgresql94-server"
else
  package "postgresql"
end

service "postgresql" do
  action [:enable, :start]
end

bash "create crowbar user" do
  user "postgres"
  code <<-EOH
    psql --command "CREATE USER #{node[:postgresql][:username]} \
                    PASSWORD '#{node[:postgresql][:password]}'"
EOH
  only_if do
    `sudo -u postgres psql -tAc "SELECT 1 FROM pg_user \
                                 WHERE usename='#{node[:postgresql][:username]}'"`.empty?
  end
end

bash "create database schema" do
  user "postgres"
  code <<-EOH
    psql --command "CREATE SCHEMA #{node[:postgresql][:database]} \
                    AUTHORIZATION #{node[:postgresql][:username]}"
    psql --command "CREATE DATABASE #{node[:postgresql][:database]} \
                    OWNER #{node[:postgresql][:username]}"
EOH
  only_if do
    `sudo -u postgres psql -tAc "SELECT 1 FROM information_schema.schemata \
                                 WHERE schema_name = '#{node[:postgresql][:database]}'"`.empty?
  end
end

bash "grant permissions" do
  user "postgres"
  code <<-EOH
    psql --command "GRANT ALL PRIVILEGES ON ALL TABLES \
                    IN SCHEMA #{node[:postgresql][:database]} \
                    TO #{node[:postgresql][:username]}"
EOH
end
