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
require "json"
require "haml"
require "tilt/haml"
require "uri"
require "net/http"
require "net/http/digest_auth"

module Crowbar
  class Bootstrap < Sinatra::Base
    configure :development do
      register Sinatra::Reloader
    end

    set :root, File.expand_path("../../../", __FILE__)

    helpers do
      def crowbar_status(user, pass)
        digest_auth = Net::HTTP::DigestAuth.new

        uri = URI.parse("http://localhost/installer/installer/status.json")
        uri.user = user
        uri.password = pass

        h = Net::HTTP.new(uri.host, uri.port)
        req = Net::HTTP::Get.new(uri.request_uri)
        res = h.request(req)

        auth = digest_auth.auth_header(uri, res['www-authenticate'], 'GET')
        req = Net::HTTP::Get.new(uri.request_uri)
        req.add_field('Authorization', auth)

        res = h.request(req)
        return {
          code: res.code,
          body: JSON.parse(res.body)
        }
      end
    end

    get "/" do
      haml :index
    end

    get "/crowbar_status/:user/:password" do
      res = crowbar_status(params[:user], params[:password])

      status res[:code]
      json res[:body]
    end

    post "/process" do
      json foo: "bar"
    end
  end
end
