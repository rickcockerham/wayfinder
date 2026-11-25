require "json"
require "net/http"
require "openssl"
require "securerandom"
require "fileutils"
require "time"

# Keep all local verification state private and never print the usable credential.
File.umask(0o077)
directory = "/tmp/wayfinder-live-bearer-20261117"
FileUtils.mkdir_p(directory, mode: 0o700)
config = JSON.parse(File.read(File.expand_path("~/.config/wayfinder/api.json")))
nonce = SecureRandom.hex(6)
prefix = "wayfinder-smoke-#{nonce}"
token = config.fetch("token")
http = Net::HTTP.new("mywayfinder.app", 443)
http.use_ssl = true
http.verify_mode = OpenSSL::SSL::VERIFY_PEER
http.open_timeout = 10
http.read_timeout = 20
results = []
report = { started_at_utc: Time.now.utc.iso8601, request_id_prefix: prefix, results: results }

#------------------------------------------------------------------------------
# Send one bounded request and retain only nonsecret test metadata in the report.
probe = lambda do |name, request, expected_status, authorization = "Bearer #{token}"|
  request["Authorization"] = authorization unless authorization.nil?
  request["Accept"] = "application/json"
  request["User-Agent"] = "Wayfinder API verification/#{nonce}"
  request["X-Request-Id"] = "#{prefix}-#{name}"
  response = http.request(request)
  body = JSON.parse(response.body) rescue nil
  passed = response.code.to_i == expected_status
  results << { name: name, method: request.method, path: request.path,
               status: response.code.to_i, passed: passed,
               request_id: response["X-Request-Id"], cache_control: response["Cache-Control"],
               has_csrf_token: !response["X-CSRF-Token"].nil?, has_set_cookie: !response["Set-Cookie"].nil? }
  File.write(File.join(directory, "report.json"), JSON.pretty_generate(report) + "\n")
  puts "#{passed ? 'PASS' : 'FAIL'} #{name}: #{response.code}"
  abort "Unexpected status during #{name}; stopped without further mutations" unless passed
  [body, response]
end

# Verify protected reads and metadata before creating any disposable item.
listing, response = probe.call("list", Net::HTTP::Get.new("/api/items?limit=1&include_choices=1"), 200)
abort "Bearer response unexpectedly issued browser state" if response["X-CSRF-Token"] || response["Set-Cookie"]
abort "Bearer response is not private" unless response["Cache-Control"] == "no-store"
category_id = listing.dig("choices", "categories", 0, "id")
mood_id = listing.dig("choices", "moods", 0, "id")
abort "No existing category or mood available for the smoke test" unless category_id && mood_id
probe.call("anonymous", Net::HTTP::Get.new("/api/items"), 401, nil)
probe.call("wrong-token", Net::HTTP::Get.new("/api/items"), 401, "Bearer invalid-smoke-#{nonce}")
probe.call("routing", Net::HTTP::Get.new("/api/not-a-real-route"), 404)
probe.call("website", Net::HTTP::Get.new("/"), 302)

# Create exactly one uniquely marked, nonrecurring item with no user associations beyond catalog choices.
marker = "Temporary API verification #{Time.now.utc.iso8601} #{nonce}"
request = Net::HTTP::Post.new("/api/items")
request["Content-Type"] = "application/json"
request.body = JSON.generate(item: { title: marker, category_id: category_id, mood_id: mood_id,
                                    notes: "Disposable automated API verification; no inventory or recurrence.",
                                    done: false, recurrence_kind: "no_recurrence" })
created, = probe.call("create", request, 201)
item = created.fetch("item")
item_id = Integer(item.fetch("id"))
abort "Create returned an unexpected test record" unless item.fetch("title") == marker && item_id.positive?
report[:created_test_item] = { id: item_id, original_title: marker, final_title: "#{marker} (PUT verified)",
                               category_id: category_id, mood_id: mood_id, nonce: nonce }
File.write(File.join(directory, "report.json"), JSON.pretty_generate(report) + "\n")

# Exercise both update verbs, preserving omitted fields and avoiding completion side effects.
read, = probe.call("read", Net::HTTP::Get.new("/api/items/#{item_id}"), 200)
abort "Read returned another item" unless read.dig("item", "title") == marker
request = Net::HTTP::Patch.new("/api/items/#{item_id}")
request["Content-Type"] = "application/json"
request.body = JSON.generate(item: { notes: "PATCH verified #{nonce}" })
patched, = probe.call("patch", request, 200)
abort "PATCH did not persist" unless patched.dig("item", "notes") == "PATCH verified #{nonce}"
request = Net::HTTP::Put.new("/api/items/#{item_id}")
request["Content-Type"] = "application/json"
request.body = JSON.generate(item: { title: "#{marker} (PUT verified)" })
updated, = probe.call("put", request, 200)
abort "PUT did not preserve the prior update" unless updated.dig("item", "notes") == "PATCH verified #{nonce}"

# Confirm invalid input fails without changing the temporary record.
request = Net::HTTP::Patch.new("/api/items/#{item_id}")
request["Content-Type"] = "application/json"
request.body = JSON.generate(item: { deadline: "2026-02-31" })
probe.call("validation", request, 422)
verified, = probe.call("verify", Net::HTTP::Get.new("/api/items/#{item_id}"), 200)
item = verified.fetch("item")
abort "Temporary test item changed unexpectedly" unless item.fetch("title") == "#{marker} (PUT verified)" && item["parent_id"].nil? && item["done"] == false && item["recurrence_kind"] == "no_recurrence" && item["deadline"].nil?
report[:verified_disposable] = true
File.write(File.join(directory, "report.json"), JSON.pretty_generate(report) + "\n")
puts JSON.generate(test_item: report[:created_test_item], verified_disposable: true, report: File.join(directory, "report.json"))
