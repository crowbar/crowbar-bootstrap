ROOT = File.expand_path("../..", __FILE__)
ENVIRONMENT = ENV["CROWBAR_INIT_ENV"] || "production"

THREADS = ENV["CROWBAR_INIT_THREADS"] || 10
WORKERS = ENV["CROWBAR_INIT_WORKERS"] || 5

LISTEN = ENV["CROWBAR_INIT_LISTEN"] || "127.0.0.1"
PORT = ENV["CROWBAR_INIT_PORT"] || 4567

require "fileutils"
require "rack/test"

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
