#
# Copyright 2016, SUSE Linux GmbH
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

#
# First ensure you have the necessary gems by cd'ing to this directory and
# running 'bundle install'. Then use as follows:
#
#   $ export GUARD_RELEASE_NAME=development # Default `development`
#   $ export GUARD_SYNC_USER=root # Default `root`
#   $ export GUARD_SYNC_HOST=192.168.124.10 # Default `192.168.124.10`
#   $ export GUARD_SYNC_PORT=22 # Default `22`
#   $ export GUARD_SYNC_TARGET=/opt/crowbar # Default `/opt/crowbar`
#   $ bundle exec guard
#
# Now all required files and directories are getting synchronized with the
# admin node so you can work with this crowbar files now. More about Guard
# at https://github.com/guard/guard#readme.
#

def value_for(variable, default)
  target = if ENV[variable]
    ENV[variable]
  else
    default
  end

  raise "#{variable} has to be non-empty" if target.empty?

  target
end

user = value_for(
  "GUARD_SYNC_USER",
  "root"
)

host = value_for(
  "GUARD_SYNC_HOST",
  "192.168.124.10"
)

port = value_for(
  "GUARD_SYNC_PORT",
  "22"
)

notification :off

group :tree do
  target = value_for(
    "GUARD_SYNC_TARGET",
    "/opt/crowbar/crowbar-init"
  )

  exclude = File.expand_path(
    "../.guard-exclude",
    __FILE__
  )

  File.open(exclude, "w") do |file|
    file.write "+ /*\n"
    file.write "- .KEEP_ME\n"
    file.write "- *.swp\n"
  end

  config_params = [
    "-ar --stats --cvs-exclude --delete",
    "--chown 'crowbar:crowbar'",
    "--exclude-from '#{exclude}'",
    "-e 'ssh -p #{port}'",
    ".",
    "#{user}@#{host}:#{target}"
  ]

  guard "remote-sync", sync_on_start: true, source: ".", cli_options: config_params.join(" ") do
    watch(/.*/)
  end
end

guard :rspec, all_on_start: true, cmd: "bundle exec rspec" do
  require "guard/rspec/dsl"
  dsl = Guard::RSpec::Dsl.new(self)

  rspec = dsl.rspec
  watch(rspec.spec_helper) { rspec.spec_dir }
  watch(rspec.spec_support) { rspec.spec_dir }
  watch(rspec.spec_files)

  ruby = dsl.ruby
  dsl.watch_spec_files_for(ruby.lib_files)
end

guard :rubocop, all_on_start: true, cli: "-c .hound.ruby.yml" do
  watch(%r{.+\.rb$})

  watch(%r{(?:.+/)?\.houn\..*\.yml$}) do |m|
    File.dirname(m[0])
  end
end
