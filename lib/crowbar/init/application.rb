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

module Crowbar
  module Init
    #
    # Sinatra based web application
    #
    class Application < Sinatra::Base
      set :server, :puma
      set :root, File.expand_path("../../../..", __FILE__)
      set :bind, "0.0.0.0"
      set :logging, true
      set :haml, format: :html5, attr_wrapper: "\""

      set :sprockets, Sprockets::Environment.new(root)
      set :assets_prefix, "/assets"
      set :digest_assets, false

      before do
        logger.level = Logger::DEBUG
      end

      configure do
        logpath = if settings.environment == :development
          "#{settings.root}/log/#{settings.environment}.log"
        else
          "/var/log/crowbar/crowbar_init_#{settings.environment}.log"
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

        def chef_config_path
          Pathname.new("#{settings.root}/chef")
        end

        def chef(attributes)
          run_list = attributes[:run_list].first

          logger.debug("Running chef solo with: #{run_list}")
          Tempfile.open("chef_solo_json_attributes") do |f|
            f.write(attributes.to_json)
            f.close
            cmd = [
              "sudo",
              "chef-solo",
              "-c #{chef_config_path}/solo.rb",
              "-j #{f.path}",
              "-o '#{run_list}'"
            ].join(" ")

            run_cmd(cmd)
          end
        end

        def run_cmd(*args)
          Open3.popen3(*args) do |stdin, stdout, stderr, wait_thr|
            {
              stdout: stdout.gets(nil),
              stderr: stderr.gets(nil),
              exit_code: wait_thr.value.exitstatus
            }
          end
        end

        def test_db_connection(attributes)
          conn = PG.connect(
            user: attributes[:username],
            password: attributes[:password],
            host: attributes[:host],
            port: attributes[:port],
            dbname: attributes[:database]
          )
          conn.status
        ensure
          conn.close if conn
        end

        def installer_url
          "http://localhost:3000/installer/installer"
        end

        def status_url
          "#{installer_url}/status.json"
        end

        def symlink_apache_to(name)
          crowbar_apache_conf = "#{crowbar_apache_path}/crowbar.conf.partial"
          crowbar_apache_conf_partial = "crowbar-#{name}.conf.partial"

          logger.debug(
            "Creating symbolic link for #{crowbar_apache_conf} to #{crowbar_apache_conf_partial}"
          )
          run_cmd(
            "sudo",
            "ln",
            "-sf",
            crowbar_apache_conf_partial,
            crowbar_apache_conf
          )
        end

        def reload_apache
          logger.debug("Reloading apache")
          run_cmd(
            "sudo",
            "systemctl",
            "reload",
            "apache2.service"
          )
        end

        def crowbar_apache_path
          "/etc/apache2/conf.d"
        end

        def crowbar_service(action)
          logger.debug("#{action.capitalize}ing crowbar service")
          run_cmd(
            "sudo",
            "systemctl",
            action.to_s,
            "crowbar.service"
          )
        end

        def crowbar_status(request_type = :html)
          uri = if request_type == :html
            URI.parse(installer_url)
          else
            URI.parse(status_url)
          end

          res = Net::HTTP.new(
            uri.host,
            uri.port
          ).request(
            Net::HTTP::Get.new(
              uri.request_uri
            )
          )

          body = if request_type == :html
            res.body
          else
            JSON.parse(res.body)
          end

          {
            code: res.code,
            body: body
          }
        rescue
          {
            code: 500,
            body: nil
          }
        end

        # TODO: this method needs to be refactored a bit in general
        def wait_for_crowbar
          logger.debug("Waiting for crowbar to become available")
          begin
            # TODO: add a timeout handling and set the status in case of a timeout
            sleep 1 until crowbar_status[:body]
            sleep 1 until crowbar_status[:body].include? "installer-installers"

            # apache takes some time to perform the final switch
            # TODO: implement a busyloop
            sleep 15
            {
              stdout: "",
              stderr: "",
              exit_code: 0
            }
          rescue => e
            {
              stdout: "",
              stderr: e.message.inspect,
              exit_code: 1
            }
          end
        end

        def api_version(version)
          major, minor = version.to_s.split(".").map(&:to_i)
          version_mime = %r(^application/vnd\.crowbar-init\.v(?<major>\d+).(?<minor>\d+)\+json$)

          versions = version_mime.match(request.accept.first.entry)
          return true if versions &&
              versions[:major].to_i == major &&
              versions[:minor].to_i == minor
          halt 406, { "Content-Type" => "application/vnd.crowbar-init.v#{major}.#{minor}+json" }, ""
        end
      end

      get "/" do
        api_version(1.0)
        status = {
          code: 501,
          body: nil
        }

        json(status)
      end

      # api :POST, "Initialize Crowbar"
      # api_version "1.0"
      post "/init" do
        api_version(1.0)
        status = {
          code: 200,
          body: nil
        }

        [
          [:crowbar_service, :start],
          [:symlink_apache_to, :rails],
          [:reload_apache],
          [:wait_for_crowbar]
        ].each do |command|
          cmd_ret = send(*command)
          next if cmd_ret[:exit_code] == 0

          message = if cmd_ret[:stdout].nil? || cmd_ret[:stdout].empty?
            cmd_ret[:stderr]
          else
            cmd_ret[:stdout]
          end

          status[:code] = 500
          status[:body] = {
            error: "#{command.inspect}: #{message}"
          }
        end

        json(status)
      end

      # api :POST, "Reset Crowbar"
      # api_version "1.0"
      post "/reset" do
        api_version(1.0)
        status = {
          code: 200,
          body: nil
        }

        [
          [:crowbar_service, :stop],
          [:symlink_apache_to, :sinatra],
          [:reload_apache]
        ].each do |command|
          cmd_ret = send(*command)
          next if cmd_ret[:exit_code] == 0

          message = if cmd_ret[:stdout].nil? || cmd_ret[:stdout].empty?
            cmd_ret[:stderr]
          else
            cmd_ret[:stdout]
          end

          status[:code] = 500
          status[:body] = {
            error: message
          }
        end

        json(status)
      end

      # api :GET, "Crowbar status"
      # api_version "1.0"
      get "/status" do
        api_version(1.0)
        json crowbar_status(:json)
      end

      # api :POST, "Create a new Crowbar database"
      # param :username, String, desc: "Username"
      # param :password, String, desc: "Password"
      # param :database, String, desc: "Database name"
      # param :host, String, desc: "External database host"
      # param :port, Integer, desc: "External database port"
      # api_version "1.0"
      post "/database/test" do
        api_version(1.0)
        attributes = {
          username: params[:username] || "crowbar",
          password: params[:password] || "crowbar",
          database: params[:database] || "crowbar_production",
          host: params[:host] || "localhost",
          port: params[:port] || 5432
        }

        logger.debug("Testing connectivity to database")
        begin
          if test_db_connection(attributes)
            json(
              code: 200,
              body: nil
            )
          else
            json(
              code: 503,
              body: {
                error: "Could not connect to database"
              }
            )
          end
        rescue => e
          json(
            code: 500,
            body: {
              error: e.message.inspect
            }
          )
        end
      end

      # api :POST, "Create a new Crowbar database"
      # param :username, String, desc: "Username"
      # param :password, String, desc: "Password"
      # api_version "1.0"
      post "/database/new" do
        api_version(1.0)
        attributes = {
          postgresql: {
            username: params[:username],
            password: params[:password]
          },
          run_list: ["recipe[postgresql::default]"]
        }

        logger.debug("Creating Crowbar database")
        if chef(attributes)[:exit_code] == 0
          json(
            code: 200,
            body: nil
          )
        else
          json(
            code: 500,
            body: {
              error: "Could not create database. Please have a look at /var/log/chef/solo.log"
            }
          )
        end
      end

      # api :POST, "Connect Crowbar to an existing external database"
      # param :username, String, desc: "External database username"
      # param :password, String, desc: "External database password"
      # param :database, String, desc: "Database name"
      # param :host, String, desc: "External database host"
      # param :port, Integer, desc: "External database port"
      # api_version "1.0"
      post "/database/connect" do
        api_version(1.0)
        attributes = {
          postgresql: {
            username: params[:username],
            password: params[:password],
            database: params[:database],
            host: params[:host],
            port: params[:port],
            remote: true
          },
          run_list: ["recipe[postgresql::config]"]
        }

        logger.debug("Connecting Crowbar to external database")
        if chef(attributes)[:exit_code] == 0
          json(
            code: 200,
            body: nil
          )
        else
          json(
            code: 500,
            body: {
              error: "Could not connect to database. Please have a look at /var/log/chef/solo.log"
            }
          )
        end
      end

      # internal API endpoint
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
