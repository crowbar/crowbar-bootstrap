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

bash "psql --command \"CREATE USER #{node[:postgresql][:username]} PASSWORD '#{node[:postgresql][:password]}'\"" do
  user "postgres"
  not_if "psql --command \"SELECT * FROM pg_user WHERE usename='#{node[:postgresql][:username]}'\""
end

bash "psql --command \"CREATE SCHEMA #{node[:postgresql][:database]}\"" do
  user "postgres"
  not_if "psql --command \"SELECT schema_name FROM information_schema.schemata WHERE schema_name = '#{node[:postgresql][:database]}'\""
end

bash "psql --command \"GRANT ALL ON SCHEMA #{node[:postgresql][:database]} TO #{node[:postgresql][:username]};\"" do
  user "postgres"
end
