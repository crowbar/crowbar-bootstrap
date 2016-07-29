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

source "https://rubygems.org"

gem "chef", "~> 10.32.2"
gem "puma", ">= 2.11.3"
gem "sprockets-helpers", ">= 1.1.0"
gem "tilt", ">= 1.4.1"
gem "json", ">= 1.4.4", "<= 1.8.1"
gem "sinatra", ">= 1.4.6"
gem "sinatra-contrib", ">= 1.4.7"
gem "haml", ">= 4.0.6"
gem "sass", ">= 3.4.13"
gem "bootstrap-sass", ">= 3.3.5"
gem "font-awesome-sass", ">= 4.5.0"
gem "uglifier", ">= 2.7.2"
gem "pg", "~> 0.17.1"

unless ENV["PACKAGING"] && ENV["PACKAGING"] == "yes"
  group :test do
    if ENV["CODECLIMATE_REPO_TOKEN"]
      gem "coveralls", require: false
      gem "codeclimate-test-reporter", require: false
    end
    gem "simplecov", require: false
    gem "rubocop", require: false
  end

  group :development do
    gem "bundler"
    gem "rake"
    gem "yard"
    gem "rspec"
    gem "webmock"
    gem "listen", "<= 3.0.6"
    gem "guard"
    gem "guard-remote-sync"
    gem "guard-rspec"
    gem "guard-rubocop"
  end
end
