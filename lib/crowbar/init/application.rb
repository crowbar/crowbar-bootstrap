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
require "sass"
require "sprockets"
require "sprockets-helpers"
require "bootstrap-sass"
require "font-awesome-sass"

module Crowbar
  module Init
    #
    # Sinatra based web application
    #
    class Application < Sinatra::Base
      set :root, File.expand_path("../../../..", __FILE__)
      set :bind, "0.0.0.0"
      set :logging, Logger::DEBUG
      set :haml, format: :html5, attr_wrapper: "\""

      set :sprockets, Sprockets::Environment.new(root)
      set :assets_prefix, "/assets"
      set :digest_assets, false

      configure do
        logpath = if settings.environment == :development
          "#{settings.root}/log/#{settings.environment}.log"
        else
          "/var/log/crowbar-init/#{settings.environment}.log"
        end
        logfile = File.new(logpath, "a+")
        logfile.sync = true
        use Rack::CommonLogger, logfile

        sprockets.append_path File.join(root, "assets", "stylesheets")
        sprockets.append_path File.join(root, "vendor", "assets", "stylesheets")

        sprockets.append_path File.join(root, "assets", "javascripts")
        sprockets.append_path File.join(root, "vendor", "assets", "javascripts")

        Sprockets::Helpers.configure do |config|
          config.environment = sprockets
          config.prefix = assets_prefix
          config.digest = digest_assets
          config.public_path = public_folder
          config.debug = true if development?
        end
      end

      configure :development do
        register Sinatra::Reloader
      end

      helpers do
        include Sprockets::Helpers

        def status_url
          "http://localhost:3000/installer/installer/status.json"
        end

        def symlink_apache_to(name)
          crowbar_apache_conf = "#{crowbar_apache_path}/crowbar.conf"
          crowbar_apache_conf_partial = "crowbar-#{name}.conf.partial"

          logger.debug(
            "Creating symbolic link for #{crowbar_apache_conf} to #{crowbar_apache_conf_partial}"
          )
          system(
            "sudo",
            "ln",
            "-sf",
            crowbar_apache_conf_partial,
            crowbar_apache_conf
          )
        end

        def reload_apache
          logger.debug("Reloading apache")
          system(
            "sudo",
            "systemctl",
            "reload",
            "apache2.service"
          )
        end

        def crowbar_apache_path
          "/etc/apache2/conf.d/crowbar"
        end

        def cleanup_db
          logger.debug("Creating and migrating crowbar database")
          Dir.chdir("/opt/dell/crowbar_framework") do
            system(
              "RAILS_ENV=production",
              "bin/rake",
              "db:cleanup"
            )
          end
        end

        def crowbar_service(action)
          logger.debug("#{action.capitalize}ing crowbar service")
          system(
            "sudo",
            "systemctl",
            action.to_s,
            "crowbar.service"
          )
        end
      end

      get "/" do
        haml :index
      end

      post "/init" do
        cleanup_db
        crowbar_service(:start)
        symlink_apache_to(:rails)
        reload_apache

        redirect "/"
      end

      post "/reset" do
        crowbar_service(:stop)
        cleanup_db
        symlink_apache_to(:sinatra)
        reload_apache

        redirect "/"
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

      get "/assets/*" do
        settings.sprockets.call(
          env.merge(
            "PATH_INFO" => params[:splat].first
          )
        )
      end
    end
  end
end
