#!/usr/bin/env bash
set -euo pipefail
cd /var/www/wayfinder
wayfinder_pid=$(systemctl show wayfinder -p MainPID --value)
wayfinder_ruby=$(readlink -f "/proc/${wayfinder_pid}/exe")
"$wayfinder_ruby" - "$wayfinder_pid" <<'RUBY'
require "json"
require "digest"
require "etc"
pid = Integer(ARGV.fetch(0))
# Verify deployment-specific files without exposing their contents.
protected_files = JSON.parse(File.read("/var/backups/wayfinder-api-20261117/preexisting-files.json"))
changed = protected_files.keys.reject { |path| File.file?(path) && Digest::SHA256.file(path).hexdigest == protected_files[path] }
abort "Pre-existing deployment files changed: #{changed.join(', ')}" unless changed.empty?
puts "Preserved all #{protected_files.length} pre-existing local files"
service_env = File.binread("/proc/#{pid}/environ").split("\0").map { |entry| entry.split("=", 2) }.to_h
ruby_exe = File.realpath("/proc/#{pid}/exe")
account = Etc.getpwnam("deploy")
group = Etc.getgrnam("www-data").gid
Process.initgroups("deploy", group)
Process::GID.change_privilege(group)
Process::UID.change_privilege(account.uid)
# Query only the verification requests and nonsecret deployment diagnostics.
code = <<~'RAILS'
  require "ipaddr"
  prefix = "wayfinder-smoke-683c30975b6d"
  expected = {"list"=>200,"anonymous"=>401,"wrong-token"=>401,"routing"=>404,"create"=>201,"read"=>200,"patch"=>200,"put"=>200,"validation"=>422,"verify"=>200,"delete"=>200,"deleted-read"=>404}
  rows = ApiRequestLog.where("request_id LIKE ?", "#{prefix}-%").order(:id).to_a
  failures = expected.filter_map do |name, status|
    matches = rows.select { |row| row.request_id == "#{prefix}-#{name}" }
    name unless matches.length == 1 && matches.first.status == status && matches.first.remote_ip.present? && matches.first.peer_ip.present? && matches.first.requested_at.present? && matches.first.duration_ms >= 0
  end
  abort "Audit mismatch for #{failures.join(', ')}" unless failures.empty?
  digest = ENV.fetch("WAYFINDER_API_TOKEN_SHA256")
  authenticated = rows.reject { |row| %w[anonymous wrong-token routing].any? { |name| row.request_id == "#{prefix}-#{name}" } }
  abort "Authenticated audit identity mismatch" unless authenticated.all? { |row| row.user_id == 1 && row.authentication_method == "bearer" && row.token_fingerprint == digest }
  abort "Audit captured only the reverse proxy address" unless rows.all? { |row| !IPAddr.new(row.remote_ip).loopback? && IPAddr.new(row.peer_ip).loopback? }
  abort "Temporary verification item remains" if Item.exists?(246)
  abort "Usable-token column unexpectedly exists" if (ApiRequestLog.column_names & %w[token authorization access_key cookie body query]).any?
  puts JSON.generate(audited_verification_requests: rows.length, all_expected_statuses_logged: true, all_ips_and_dates_present: true, actual_client_ips_separated_from_proxy: true, verified_owner_and_token_fingerprint: true, temporary_item_deleted: true, owner_item_count: User.find(1).items.count, log_rows_total: ApiRequestLog.count, migration_version: ActiveRecord::Base.connection.migration_context.current_version, service_token_configured: digest.match?(/\A[0-9a-f]{64}\z/))
RAILS
exec(service_env, ruby_exe, "bin/rails", "runner", code)
RUBY
systemctl is-active wayfinder
