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

# root_path specifies the root path of the crowbar-init application

root_path = File.expand_path("../..", __FILE__)

# log_level specifies the level of verbosity for output.
# valid values are: :debug, :info, :warn, :error, :fatal

log_level :debug

# log_location specifies where chef-solo should log to.
# valid values are: a quoted string specifying a file, or STDOUT with
# no quotes. This is the application log for the Merb workers that get
# spawned.

log_location "/var/log/chef/solo.log"

# ssl_verify_mode specifies if the REST client should verify SSL certificates.
# valid values are :verify_none, :verify_peer. The default Chef Server
# installation on Debian will use a self-generated SSL certificate so this
# should be :verify_none unless you replace the certificate.

ssl_verify_mode :verify_peer

# cookbook_path is a Ruby array of filesystem locations to search for cookbooks
# that are available for chef-solo.
#
# valid value is a string, or an array of strings of filesystem directory locations.
# This setting is searched beginning (index 0) to end in order. You might specify
# multiple search paths for cookbooks if you want to use an upstream source, and
# provide localised "site" overrides. These should come after the 'upstream' source.
# The default value, /var/lib/chef/cookbooks does not contain any cookbooks by default.

cookbook_path [File.join(root_path, "chef", "cookbooks")]

# file_cache_path specifies where chef should cache cookbooks, server
# cookie ID, and openid registration data.
# valid value is any filesystem directory location.

file_cache_path "/var/cache/chef"

# cache_options sets options used by the moneta library for local cache
# for checksums of compared objects.

cache_options(path: "/var/cache/chef/checksums", skip_expires: true)
