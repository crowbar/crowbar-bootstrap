ROOT = File.expand_path("../..", __FILE__)
ENVIRONMENT = ENV["CROWBAR_INIT_ENV"] || "production"

THREADS = ENV["CROWBAR_INIT_THREADS"] || 5
WORKERS = ENV["CROWBAR_INIT_WORKERS"] || 1

LISTEN = ENV["CROWBAR_INIT_LISTEN"] || "127.0.0.1"
PORT = ENV["CROWBAR_INIT_PORT"] || 4567

CROWBAR_LIB_DIR = "/opt/dell/crowbar_framework/lib".freeze

require "fileutils"
require "rack/test"

$LOAD_PATH.push CROWBAR_LIB_DIR if Dir.exist?(CROWBAR_LIB_DIR)

directory ROOT
environment ENVIRONMENT

tag "crowbar-init"

quiet
preload_app!

daemonize false
prune_bundler false

threads 0, THREADS

workers WORKERS
worker_timeout 60

pidfile File.join(ROOT, "tmp", "pids", "puma.pid")
state_path File.join(ROOT, "tmp", "pids", "puma.state")

bind "tcp://#{LISTEN}:#{PORT}"

[
  "tmp/pids",
  "tmp/sessions",
  "tmp/sockets",
  "tmp/cache"
].each do |name|
  FileUtils.mkdir_p File.join(ROOT, name)
end

# set the end_step status during the upgrade
if File.exist?("/var/lib/crowbar/upgrade/6-to-7-progress.yml")
  require "logger"
  require "crowbar/upgrade_status"
  upgrade_status = ::Crowbar::UpgradeStatus.new(Logger.new(Logger::STDOUT))
  upgrade_status.end_step if upgrade_status.current_step == :admin
end
