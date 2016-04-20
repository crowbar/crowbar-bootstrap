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

require "sinatra/base"
require "sinatra/json"
require "sinatra/reloader"
require "haml"
require "tilt/haml"
require "json"
require "uri"
require "net/http"

module Crowbar
  module Init
    class Application < Sinatra::Base
      configure :development do
        register Sinatra::Reloader
      end

      set :root, File.expand_path("../../../..", __FILE__)
      set :bind, "0.0.0.0"
      set :haml, { format: :html5 }

      get "/" do
        haml :index
      end

      post "/init" do
        json foo: "bar"
      end

      get "/status" do
        uri = URI.parse(
          status_url
        )

        result = begin
          res = Net::HTTP.new(
            uri.host,
            uri.port
          ).request(
            Net::HTTP::Get.new(
              uri.request_uri
            )
          )

          {
            code: res.code,
            body: JSON.parse(res.body)
          }
        rescue
          {
            code: 500,
            body: nil
          }
        end

        json result
      end

      protected

      def status_url
        "http://localhost:3000/installer/installer/status.json"
      end
    end
  end
end
