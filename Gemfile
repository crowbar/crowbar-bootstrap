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
gemspec

group :development do
  gem "guard", require: false
  gem "guard-rubocop", require: false
  gem "guard-rspec", require: false
end

group :test do
  gem "simplecov", require: false
  gem "coveralls", require: false
  gem "codeclimate-test-reporter", require: false
  gem "rubocop", require: false
end

instance_eval(File.read("Gemfile.local")) if File.exist? "Gemfile.local"
