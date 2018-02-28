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

require "fileutils"
require "timeout"

module Crowbar
  module Init
    module Helpers
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

          return run_cmd(cmd)
        end
      end

      def run_cmd(*args)
        Open3.popen2e(*args) do |stdin, stdout_and_stderr, wait_thr|
          {
            stdout_and_stderr: stdout_and_stderr.gets(nil),
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

      def crowbar_framework_path
        "/opt/dell/crowbar_framework"
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

      def crowbar_jobs_service(action)
        logger.debug("#{action.capitalize}ing crowbar-jobs service")
        run_cmd(
          "sudo",
          "systemctl",
          action.to_s,
          "crowbar-jobs.service"
        )
      end

      def shutdown_crowbar_init
        logger.debug("Shutting down crowbar-init service")
        cmd_ret = run_cmd(
          "sudo",
          "systemctl",
          "disable",
          "crowbar-init.service"
        )
        return cmd_ret unless cmd_ret[:exit_code].zero?

        Thread.new do
          # wait a bit to let the API request come back with 200
          sleep 10
          cmd_ret = run_cmd(
            "sudo",
            "systemctl",
            "stop",
            "crowbar-init.service"
          )
        end

        cmd_ret
      end

      def crowbar_request(url, request_type = :get, response_type = :html)
        uri = URI.parse(url)

        req = if request_type == :post
          Net::HTTP::Post.new(
            uri.request_uri
          )
        else
          Net::HTTP::Get.new(
            uri.request_uri
          )
        end

        res = Net::HTTP.new(
          uri.host,
          uri.port
        ).request(
          req
        )

        body = if response_type == :html
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

      def crowbar_status(response_type = :html)
        crowbar_request(response_type == :html ? installer_url : status_url,
                        :get,
                        response_type)
      end

      # TODO: this method needs to be refactored a bit in general
      def wait_for_crowbar
        logger.debug("Waiting for crowbar to become available")
        begin
          Timeout::timeout(120) {
            sleep 1 until crowbar_status[:body]
          }
          Timeout::timeout(30) {
            sleep 1 until crowbar_status[:body].include? "installer-installers"
          }

          # apache takes some time to perform the final switch
          # TODO: implement a busyloop
          sleep 15
          {
            message: "",
            exit_code: 0
          }
        rescue Timeout::Error
          msg = "Timout while waiting for crowbar to become available"
          logger.error(msg)
          {
            stdout_and_stderr: msg,
            exit_code: 2
          }
        rescue => e
          {
            stdout_and_stderr: e.message.inspect,
            exit_code: 1
          }
        end
      end

      def api_constraint(*versions)
        versions = versions.map { |v| v.to_s.split(".").map(&:to_i) }
        versions.any? do |major, minor|
          version_mime = %r(^application/vnd\.crowbar\.v(?<major>\d+).(?<minor>\d+)\+json$)

          versions_requested = version_mime.match(request.accept.first.entry)
          break if versions_requested.nil?
          return true if versions_requested[:major].to_i == major &&
              versions_requested[:minor].to_i <= minor
        end

        halt 406, {
          "Content-Type" => "application/vnd.crowbar.v#{Crowbar::Init::Version.api_latest}+json"
        }, ""
      end

      def migrate_database
        ["data.yml", "schema.rb"].each do |file|
          file_path = "#{crowbar_framework_path}/db/#{file}"
          backup_file_path = "/var/lib/crowbar/upgrade/#{file}"
          next if File.exist?(file_path)
          logger.warn("Could not find #{file_path}. Using #{backup_file_path}.")
          unless File.exist?(backup_file_path)
            logger.error("Could not find #{backup_file_path} either.")
            return {
              stdout_and_stderr: "Could not find database dump in #{file_path} " \
                                 "or backup in #{backup_file_path}.",
              exit_code: 1
            }
          end
          FileUtils.cp(backup_file_path, file_path, preserve: true)
        end

        run_cmd("cd /opt/dell/crowbar_framework && RAILS_ENV=production bin/rake db:load")
      end

      def migrate_crowbar
        logger.debug("Migrating crowbar schemas")
        run_cmd(
          "cd /opt/dell/crowbar_framework && " \
          "RAILS_ENV=production bin/rake crowbar:schema_migrate_prod"
        )
      end

      def update_config_db
        logger.debug("Updating crowbar configuration DB")
        run_cmd(
          "cd /opt/dell/crowbar_framework && " \
          "RAILS_ENV=production bin/rake crowbar:update_config_db"
        )
      end

      def seed_db
        logger.debug("Seeding crowbar database")
        run_cmd(
          "cd /opt/dell/crowbar_framework && " \
          "RAILS_ENV=production bin/rake db:seed"
        )
      end

      def crowbar_init
        status = {
          code: 200,
          body: nil
        }

        [
          [:crowbar_service, :start],
          [:crowbar_jobs_service, :enable],
          [:crowbar_jobs_service, :start],
          [:wait_for_crowbar],
          [:migrate_crowbar],
          [:update_config_db],
          [:seed_db],
          [:symlink_apache_to, :rails],
          [:reload_apache],
          [:shutdown_crowbar_init]
        ].each do |command|
          cmd_ret = send(*command)
          next if cmd_ret[:exit_code].zero?

          errmsg = "#{command.join}: #{cmd_ret[:stdout_and_stderr]}"
          logger.error(errmsg)

          status[:code] = 500
          status[:body] = {
            data: errmsg,
            help: "Refer to the error message in the response."
          }

          break
        end

        status
      end

      def crowbar_reset
        status = {
          code: 200,
          body: nil
        }

        [
          [:crowbar_service, :stop],
          [:crowbar_jobs_service, :disable],
          [:crowbar_jobs_service, :stop],
          [:symlink_apache_to, :sinatra],
          [:reload_apache]
        ].each do |command|
          cmd_ret = send(*command)
          next if cmd_ret[:exit_code].zero?

          errmsg = "#{command.inspect}: #{cmd_ret[:stdout_and_stderr]}"
          logger.error(errmsg)

          status[:code] = 500
          status[:body] = {
            error: errmsg
          }

          break
        end

        status
      end
    end
  end
end
