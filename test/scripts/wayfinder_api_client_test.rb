require "minitest/autorun"
require "minitest/mock"
require "fileutils"
require "json"
require "net/http"
require "openssl"
require "stringio"
require "tmpdir"

class WayfinderApiClientTest < Minitest::Test
  CLIENT = File.expand_path("../../bin/wayfinder-api", __dir__)
  TOKEN = "a" * 64

  # ----------------------------------------------------------------------------
  def setup
    # Keep each credential and payload fixture private and separate from real config.
    @directory = Dir.mktmpdir("wayfinder-api-client-test-")
    @config = File.join(@directory, "api.json")
    File.write(@config, JSON.generate("token" => TOKEN), perm: 0o600)
  end

  # ----------------------------------------------------------------------------
  def teardown
    # Remove only the temporary files created by this test.
    FileUtils.remove_entry(@directory)
  end

  # ----------------------------------------------------------------------------
  def test_get_and_delete_send_private_bearer_over_verified_fixed_tls
    # Exercise collection reads and deletion without making a real network request.
    [["get", "/api/items/priorities?limit=20"], ["get", "/api/items/priorities"],
     ["get", "/api/items?limit=1&include_choices=1"], ["delete", "/api/items/123"],
     ["get", "/api/locations?parent_id=12"], ["get", "/api/locations/12"],
     ["get", "/api/inventory_items?q=timers&include_totals=1"], ["get", "/api/inventory_items/30"]].each do |arguments|
      result = run_client(arguments)

      assert_equal 0, result[:status]
      assert_equal [["mywayfinder.app", 443]], result[:connections]
      assert_equal 1, result[:requests].length
      assert_equal arguments.first.upcase, result[:requests].first.method
      assert_equal arguments.last, result[:requests].first.path
      assert_equal "Bearer #{TOKEN}", result[:requests].first["Authorization"]
      assert_equal "application/json", result[:requests].first["Accept"]
      assert_nil result[:requests].first.body
      assert_equal true, result[:http].use_ssl?
      assert_equal OpenSSL::SSL::VERIFY_PEER, result[:http].verify_mode
      assert_equal 10, result[:http].open_timeout
      assert_equal 30, result[:http].read_timeout
      assert_equal({ "ok" => true }, JSON.parse(result[:stdout]))
      assert_empty result[:stderr]
    end
  end

  # ----------------------------------------------------------------------------
  def test_nested_location_and_inventory_writes_reuse_bearer_transport
    # Send native inventory payloads unchanged through the same private client.
    examples = [
      ["post", "/api/locations", { "location" => { "path" => ["Workshop", "Drawer"] } }],
      ["put", "/api/inventory_items", { "inventory_item" => { "name" => "Timers", "location_id" => 12, "shop_id" => 4, "unit" => "each" } }]
    ]
    examples.each do |method, path, payload|
      result = run_client([method, path, "-"], input: JSON.generate(payload))
      assert_equal 0, result[:status]
      assert_equal method.upcase, result[:requests].first.method
      assert_equal path, result[:requests].first.path
      assert_equal "Bearer #{TOKEN}", result[:requests].first["Authorization"]
      assert_equal payload, JSON.parse(result[:requests].first.body)
      assert_empty result[:stderr]
    end
  end

  # ----------------------------------------------------------------------------
  def test_json_writes_accept_file_or_stdin_and_normalize_payload
    # Cover each supported write verb and both documented payload sources.
    payload = { "item" => { "title" => "Temporary API item" } }
    payload_path = File.join(@directory, "item.json")
    File.write(payload_path, JSON.pretty_generate(payload))

    [["post", "/api/items", payload_path], ["patch", "/api/items/123", "-"], ["put", "/api/items/123", "-"]].each do |arguments|
      result = run_client(arguments, input: JSON.pretty_generate(payload))

      assert_equal 0, result[:status]
      assert_equal 1, result[:requests].length
      assert_equal arguments.first.upcase, result[:requests].first.method
      assert_equal "Bearer #{TOKEN}", result[:requests].first["Authorization"]
      assert_equal "application/json", result[:requests].first["Content-Type"]
      assert_equal JSON.generate(payload), result[:requests].first.body
      assert_empty result[:stderr]
    end
  end

  # ----------------------------------------------------------------------------
  def test_invalid_destinations_methods_and_arguments_never_open_a_connection
    # Reject origin changes, path traversal and malformed command shapes before HTTP setup.
    arguments_to_reject = [
      ["get", "https://example.com/api/items"],
      ["get", "//example.com/api/items"],
      ["get", "/api/items/../users"],
      ["get", "/api/items/%2e%2e/users"],
      ["get", "/api/locations/../users"],
      ["get", "/api/inventory_items/%2e%2e/users"],
      ["get", "/api/locations/0"],
      ["get", "/api/locations/priorities"],
      ["get", "/api/inventory_items/priorities?limit=20"],
      ["get", "/api/inventory_items/1#fragment"],
      ["get", "/api/items/1#fragment"],
      ["get", "/api/items?limit=1\r\nHost: example.com"],
      ["get", "/api/users"],
      ["trace", "/api/items"],
      ["get", "/api/items", "unexpected.json"],
      ["post", "/api/items"],
      ["delete", "/api/items/123", "unexpected.json"],
      ["get", "/api/items", "extra", "arguments"]
    ]

    arguments_to_reject.each do |arguments|
      result = run_client(arguments)

      refute_equal 0, result[:status], arguments.inspect
      assert_empty result[:connections], arguments.inspect
      assert_empty result[:requests], arguments.inspect
      assert_empty result[:stdout], arguments.inspect
    end
  end

  # ----------------------------------------------------------------------------
  def test_invalid_private_credentials_and_payloads_fail_without_disclosing_tokens
    # Reject absent, malformed and structurally invalid credential files.
    ["{broken", "123", "true", "null", JSON.generate(TOKEN), "{}", JSON.generate("token" => 123), JSON.generate("token" => "not-a-token")].each do |content|
      File.write(@config, content)
      result = run_client(["get"])

      refute_equal 0, result[:status]
      assert_empty result[:connections]
      assert_empty result[:stdout]
    end

    # Refuse credentials exposed to other users or owned by a different account.
    File.write(@config, JSON.generate("token" => TOKEN))
    File.chmod(0o644, @config)
    result = run_client(["get"])
    refute_equal 0, result[:status]
    assert_empty result[:connections]
    File.chmod(0o600, @config)
    stat = File.stat(@config)
    stat.stub(:uid, Process.uid + 1) do
      File.stub(:stat, stat) do
        result = run_client(["get"])
        refute_equal 0, result[:status]
        assert_empty result[:connections]
      end
    end

    # Validate JSON before sending, even when an input file is missing.
    [["-", "{broken"], [File.join(@directory, "missing.json"), ""]].each do |source, input|
      result = run_client(["post", "/api/items", source], input: input)
      refute_equal 0, result[:status]
      assert_empty result[:requests]
      assert_includes result[:stderr], "Cannot read a valid JSON payload"
    end

    File.unlink(@config)
    result = run_client(["get"])
    refute_equal 0, result[:status]
    assert_empty result[:connections]
  end

  # ----------------------------------------------------------------------------
  def test_http_errors_redirects_and_connection_failures_are_generic_and_nonzero
    # Error responses stay visible as API data, but redirects never trigger another request.
    [[Net::HTTPUnauthorized, "401", '{"error":"unauthorized"}'], [Net::HTTPFound, "302", "<html>Moved</html>"]].each do |klass, code, body|
      result = run_client(["get"], response: response_with_body(klass, code, body))

      refute_equal 0, result[:status]
      assert_equal 1, result[:connections].length
      assert_equal 1, result[:requests].length
      assert_includes result[:stderr], "API request failed (HTTP #{code})"
    end

    # A library exception can contain sensitive text; only the generic error should escape.
    result = run_client(["get"], error: OpenSSL::SSL::SSLError.new("certificate failure #{TOKEN}"))
    refute_equal 0, result[:status]
    assert_equal "Could not connect securely to the Wayfinder API\n", result[:stderr]
    assert_empty result[:stdout]
  end

  #-----------------------------------------------------------------------------
  def test_native_blocker_commands_preserve_direction_and_fixed_bearer_transport
    examples = [
      [["block", "123", "456"], "POST", "/api/item_blocks", { "item_block" => { "blocker_id" => 123, "blocked_id" => 456 } }],
      [["blockers", "456"], "GET", "/api/item_blocks?blocked_id=456", nil],
      [["blocks", "123"], "GET", "/api/item_blocks?blocker_id=123", nil],
      [["unblock", "789"], "DELETE", "/api/item_blocks/789", nil],
      [["get", "/api/item_blocks?limit=1&after_id=10"], "GET", "/api/item_blocks?limit=1&after_id=10", nil]
    ]
    examples.each do |arguments, method, path, payload|
      result = run_client(arguments)
      assert_equal 0, result[:status]
      request = result[:requests].fetch(0)
      assert_equal method, request.method
      assert_equal path, request.path
      payload.nil? ? assert_nil(request.body) : assert_equal(payload, JSON.parse(request.body))
      assert_equal "Bearer #{TOKEN}", request["Authorization"]
      assert_equal [["mywayfinder.app",443]], result[:connections]
    end
    [["block", "123"], ["block", "123", "0"], ["blocks", "../123"], ["unblock", "0"], ["blockers", "123", "456"]].each do |arguments|
      result = run_client(arguments)
      refute_equal 0, result[:status]
      assert_empty result[:connections]
    end
  end

  private

  # ----------------------------------------------------------------------------
  def response_with_body(klass = Net::HTTPOK, code = "200", body = '{"ok":true}')
    # Model a response already read by Net::HTTP without opening a socket.
    response = klass.new("1.1", code, "Test response")
    response.body = body
    response.instance_variable_set(:@read, true)
    response
  end

  # ----------------------------------------------------------------------------
  def run_client(arguments, input: "", response: response_with_body, error: nil)
    # Save all process-wide inputs because the executable reads them directly.
    saved_arguments = ARGV.dup
    saved_environment = ENV.to_h
    saved_stdin = $stdin
    ARGV.replace(arguments)
    ENV["WAYFINDER_API_CONFIG"] = @config
    $stdin = StringIO.new(input)

    # Stub the HTTP boundary while retaining real request objects and TLS configuration.
    connections = []
    requests = []
    http = Net::HTTP.new("example.invalid", 443)
    status = 0
    stdout, stderr = capture_io do
      Net::HTTP.stub(:new, ->(*destination) { connections << destination; http }) do
        http.stub(:request, ->(request) { requests << request; raise error if error; response }) do
          begin
            load CLIENT
          rescue SystemExit => exit
            status = exit.status
          end
        end
      end
    end

    # Every success and failure path must keep the credential out of terminal output.
    refute_includes stdout, TOKEN
    refute_includes stderr, TOKEN
    { status: status, stdout: stdout, stderr: stderr, connections: connections, requests: requests, http: http }
  ensure
    # Prevent one invocation from changing another test or the parent test process.
    ARGV.replace(saved_arguments)
    ENV.replace(saved_environment)
    $stdin = saved_stdin
  end
end
