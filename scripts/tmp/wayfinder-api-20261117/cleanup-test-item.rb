require "json"
require "net/http"
require "openssl"
require "time"

# Read only the verified item created by this task, never a user-supplied existing ID.
File.umask(0o077)
report_path = "/tmp/wayfinder-live-bearer-20261117/report.json"
report = JSON.parse(File.read(report_path))
test_item = report.fetch("created_test_item")
abort "Disposable test evidence is missing" unless report["verified_disposable"] == true && test_item["id"] == 246 && test_item["nonce"] == "683c30975b6d"
config = JSON.parse(File.read(File.expand_path("~/.config/wayfinder/api.json")))
http = Net::HTTP.new("mywayfinder.app", 443)
http.use_ssl = true
http.verify_mode = OpenSSL::SSL::VERIFY_PEER
http.open_timeout = 10
http.read_timeout = 20
headers = { "Authorization" => "Bearer #{config.fetch('token')}", "Accept" => "application/json",
            "User-Agent" => "Wayfinder API verification/#{test_item.fetch('nonce')}" }
path = "/api/items/246"

# Re-read and match its unique marker and inert fields immediately before cleanup.
response = http.request(Net::HTTP::Get.new(path, headers))
abort "Disposable item is no longer readable; no delete sent" unless response.code == "200"
item = JSON.parse(response.body).fetch("item")
matches = item["id"] == 246 && item["title"] == test_item.fetch("final_title") && item["notes"] == "PATCH verified 683c30975b6d" && item["parent_id"].nil? && item["done"] == false && item["recurrence_kind"] == "no_recurrence"
abort "Disposable item no longer matches; no delete sent" unless matches

# Delete only that newly created temporary record, then confirm it is gone.
headers["X-Request-Id"] = "#{report.fetch('request_id_prefix')}-delete"
response = http.request(Net::HTTP::Delete.new(path, headers))
abort "Temporary cleanup failed (HTTP #{response.code})" unless response.code == "200" && JSON.parse(response.body)["deleted"] == 246
report.fetch("results") << { name: "delete", method: "DELETE", path: path, status: 200, passed: true, request_id: response["X-Request-Id"] }
headers["X-Request-Id"] = "#{report.fetch('request_id_prefix')}-deleted-read"
response = http.request(Net::HTTP::Get.new(path, headers))
abort "Deleted item is still accessible" unless response.code == "404"
report.fetch("results") << { name: "deleted-read", method: "GET", path: path, status: 404, passed: true, request_id: response["X-Request-Id"] }
report["temporary_item_deleted"] = true
report["completed_at_utc"] = Time.now.utc.iso8601
File.write(report_path, JSON.pretty_generate(report) + "\n")
puts "PASS DELETE /api/items/246: 200; subsequent GET: 404"
