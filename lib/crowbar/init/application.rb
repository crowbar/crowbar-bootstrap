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

require "crowbar/upgrade_status"

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

      if ENV["RAILS_ENV"] && !ENV["RACK_ENV"]
        set :environment, ENV["RAILS_ENV"]
      end

      before do
        logger.level = Logger::DEBUG
        # parse JSON in POST requests
        if request.request_method == "POST" && request.content_type.include?("json")
          params.merge!(JSON.parse(request.body.read, symbolize_names: true))
        end
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
      end

      configure :development do
        register Sinatra::Reloader
      end

      helpers do
        include Crowbar::Init::Helpers
      end

      get "/" do
        api_constraint(2.0)
        ret = {
          code: 501,
          body: nil
        }

        status 501
        json(
          ret
        )
      end

      # api :POST, "Initialize Crowbar"
      # api_version "2.0"
      post "/api/init" do
        api_constraint(2.0)

        init = crowbar_init

        status init[:code]
        json(
          init
        )
      end

      # api :POST, "Reset Crowbar"
      # api_version "2.0"
      post "/api/reset" do
        api_constraint(2.0)

        reset = crowbar_reset

        status reset[:code]
        json(
          reset
        )
      end

      # api :POST, "Migrate crowbar schemas"
      # api_version "2.0"
      post "/api/migrate" do
        api_constraint(2.0)
        migration = migrate_crowbar
        if migration[:exit_code].zero?
          json(
            code: 200,
            body: nil
          )
        else
          logger.error(migration[:stdout_and_stderr])
          status 500
          json(
            code: 500,
            body: {
              error: migration[:stdout_and_stderr]
            }
          )
        end
      end

      # api :GET, "Crowbar status"
      # api_version "2.0"
      get "/api/status" do
        api_constraint(2.0)
        ret = {
          code: 200,
          body: {
            crowbar: crowbar_status(:json)
          }
        }

        status ret[:code]
        json(
          ret
        )
      end

      # api :POST, "Create a new Crowbar database"
      # param :username, String, desc: "Username"
      # param :password, String, desc: "Password"
      # param :database, String, desc: "Database name"
      # param :host, String, desc: "External database host"
      # param :port, Integer, desc: "External database port"
      # api_version "2.0"
      post "/api/database/test" do
        api_constraint(2.0)
        attributes = {
          username: params[:username] || "crowbar",
          password: params[:password] || "crowbar",
          database: params[:database] || "crowbar_production",
          host: params[:host] || "localhost",
          port: params[:port] || 5432
        }

        logger.debug("Testing connectivity to database")
        begin
          if test_db_connection(attributes).zero?
            json(
              code: 200,
              body: nil
            )
          else
            status 503
            json(
              code: 503,
              body: {
                error: "Could not connect to database"
              }
            )
          end
        rescue PG::ConnectionBad => e
          logger.error(e.message)
          status 406
          json(
            code: 406,
            body: {
              error: e.message
            }
          )
        end
      end

      # api :POST, "Create a new Crowbar database"
      # param :username, String, desc: "Username"
      # param :password, String, desc: "Password"
      # api_version "2.0"
      post "/api/database/new" do
        api_constraint(2.0)
        attributes = {
          postgresql: {
            username: params[:username],
            password: params[:password]
          },
          run_list: ["recipe[postgresql::default]"]
        }
        http_code = 200

        logger.debug("Creating Crowbar database")
        result = {}.tap do |res|
          chef_solo_run = chef(attributes)
          res[:database_setup] = {
            success: chef_solo_run[:exit_code].zero?
          }
          unless res[:database_setup][:success]
            logger.error(chef_solo_run[:stdout_and_stderr])
            http_code = 422
            res[:error] = chef_solo_run[:stdout_and_stderr]
            next
          end

          init = crowbar_init
          res[:crowbar_init] = {
            success: init[:code] == 200
          }

          if init[:body] # nil body means success
            logger.error(init[:body])
            res[:crowbar_init][:body] = init[:body]
            http_code = 422
          end
        end

        status http_code
        json(
          result
        )
      end

      # api :POST, "Connect Crowbar to an existing external database"
      # param :username, String, desc: "External database username"
      # param :password, String, desc: "External database password"
      # param :database, String, desc: "Database name"
      # param :host, String, desc: "External database host"
      # param :port, Integer, desc: "External database port"
      # api_version "2.0"
      post "/api/database/connect" do
        api_constraint(2.0)
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
        http_code = 200

        logger.debug("Connecting Crowbar to external database")
        result = {}.tap do |res|
          chef_solo_run = chef(attributes)
          res[:database_setup] = {
            success: chef_solo_run[:exit_code].zero?
          }
          unless res[:database_setup][:success]
            logger.error(chef_solo_run[:stdout_and_stderr])
            http_code = 422
            res[:error] = chef_solo_run[:stdout_and_stderr]
            next
          end

          init = crowbar_init
          res[:crowbar_init] = {
            success: init[:code] == 200
          }

          if init[:body] # nil body means success
            logger.error(init[:body])
            res[:crowbar_init][:body] = init[:body]
            http_code = 422
          end
        end

        status http_code
        json(
          result
        )
      end

      # api :POST, "Migrate the sqlite database to postgresql"
      post "/api/database/migrate" do
        api_constraint(2.0)
        database_migration = migrate_database
        if database_migration[:exit_code].zero?
          json(
            code: 200,
            body: nil
          )
        else
          logger.error(database_migration[:stdout_and_stderr])
          status 500
          json(
            code: 500,
            body: {
              error: database_migration[:stdout_and_stderr]
            }
          )
        end
      end

      # api :GET, "Crowbar upgrade status"
      # api_version "2.0"
      get "/api/upgrade" do
        api_constraint(2.0)
        http_code = 200
        crowbar_upgrade_status = ::Crowbar::UpgradeStatus.new(logger)
        if crowbar_upgrade_status.progress.is_a?(Hash)
          response = crowbar_upgrade_status.progress
        else
          response = {
            error: "Could not read from /var/lib/crowbar/upgrade/6-to-7-progress.yml"
          }
          http_code = 503
        end

        status http_code
        json(
          response
        )
      end

      # api :POST, "Initialization during upgrade with creation of a new database"
      # param :username, String, desc: "Username"
      # param :password, String, desc: "Password"
      # api_version "2.0"
      post "/api/upgrade/new" do
        api_constraint(2.0)
        upgrade_status = ::Crowbar::UpgradeStatus.new(logger)
        upgrade_status.start_step(:database)

        attributes = {
          postgresql: {
            username: params[:username],
            password: params[:password]
          },
          run_list: ["recipe[postgresql::default]"]
        }
        http_code = 200

        result = {}.tap do |res|
          chef_solo_run = chef(attributes)
          res[:database_setup] = {
            success: chef_solo_run[:exit_code].zero?
          }
          unless res[:database_setup][:success]
            logger.error(chef_solo_run[:stdout_and_stderr])
            res[:error] = chef_solo_run[:stdout_and_stderr]
            http_code = 422
            next
          end

          database_migration = migrate_database
          res[:database_migration] = {
            success: database_migration[:exit_code].zero?
          }
          unless res[:database_migration][:success]
            logger.error(database_migration[:stdout_and_stderr])
            http_code = 422
            res[:error] = database_migration[:stdout_and_stderr]
            next
          end

          schema_migration = migrate_crowbar
          res[:schema_migration] = {
            success: schema_migration[:exit_code].zero?
          }
          unless res[:schema_migration][:success]
            logger.error(schema_migration[:stdout_and_stderr])
            http_code = 422
            res[:error] = schema_migration[:stdout_and_stderr]
            next
          end

          init = crowbar_init
          res[:crowbar_init] = {
            success: init[:code] == 200
          }

          if init[:body] # nil body means success
            logger.error(init[:body])
            res[:error] = init[:body]
            http_code = 422
          end
        end

        if result[:error]
          upgrade_status.end_step(false, database: result[:error])
        else
          upgrade_status.end_step
        end

        status http_code
        json(
          result
        )
      end

      # api :POST, "Initialization during upgrade with connection to an existing database"
      # param :username, String, desc: "External database username"
      # param :password, String, desc: "External database password"
      # param :database, String, desc: "Database name"
      # param :host, String, desc: "External database host"
      # param :port, Integer, desc: "External database port"
      # api_version "2.0"
      post "/api/upgrade/connect" do
        api_constraint(2.0)
        upgrade_status = ::Crowbar::UpgradeStatus.new(logger)
        upgrade_status.start_step(:database)

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
        http_code = 200

        begin
          test_db_connection(attributes[:postgresql])
        rescue PG::ConnectionBad => e
          halt 406, {}, e.message
        end

        result = {}.tap do |res|
          chef_solo_run = chef(attributes)
          res[:database_setup] = {
            success: chef_solo_run[:exit_code].zero?
          }
          unless res[:database_setup][:success]
            logger.error(chef_solo_run[:stdout_and_stderr])
            http_code = 422
            res[:error] = chef_solo_run[:stdout_and_stderr]
            next
          end

          database_migration = migrate_database
          res[:database_migration] = {
            success: database_migration[:exit_code].zero?
          }
          unless res[:database_migration][:success]
            logger.error(database_migration[:stdout_and_stderr])
            http_code = 422
            res[:error] = database_migration[:stdout_and_stderr]
            next
          end

          schema_migration = migrate_crowbar
          res[:schema_migration] = {
            success: schema_migration[:exit_code].zero?
          }
          unless res[:schema_migration][:success]
            logger.error(schema_migration[:stdout_and_stderr])
            http_code = 422
            res[:error] = schema_migration[:stdout_and_stderr]
            next
          end

          init = crowbar_init
          res[:crowbar_init] = {
            success: init[:code] == 200
          }

          if init[:body] # nil body means success
            logger.error(init[:body])
            res[:error] = init[:body]
            http_code = 422
          end
        end

        if result[:error]
          upgrade_status.end_step(false, database: result[:error])
        else
          upgrade_status.end_step
        end

        status http_code
        json(
          result
        )
      end
    end
  end
end
