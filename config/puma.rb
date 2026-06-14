# threads
max_threads = Integer(ENV.fetch("RAILS_MAX_THREADS", 5))
min_threads = Integer(ENV.fetch("RAILS_MIN_THREADS", max_threads))
threads min_threads, max_threads

# workers
workers Integer(ENV.fetch("WEB_CONCURRENCY", 2))
preload_app!

# bind + files
bind "tcp://127.0.0.1:3000"
pidfile "tmp/pids/puma.pid"
state_path "tmp/pids/puma.state"

# logging
stdout_redirect "log/puma.stdout.log", "log/puma.stderr.log", true

# IMPORTANT: do NOT daemonize when using systemd
# daemonize false   # (omit entirely if you never set it)

# timeouts (keep idle client conns a bit longer)
persistent_timeout 20

environment ENV.fetch("RAILS_ENV", "production")

# optional control app (for phased restarts)
# activate_control_app "tcp://127.0.0.1:9293"


