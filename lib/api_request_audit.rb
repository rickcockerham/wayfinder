require "digest"

class ApiRequestAudit
  # ----------------------------------------------------------------------------
  def initialize(app)
    @app = app
  end

  # ----------------------------------------------------------------------------
  def call(env)
    # Include routing failures under /api, while leaving ordinary website traffic alone.
    path = env["PATH_INFO"].to_s
    return @app.call(env) unless path == "/api" || path.start_with?("/api/")

    requested_at = Time.now.utc
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    status = 500
    exception = nil
    begin
      # Sitting outside ShowExceptions records the actual HTTP response it returns.
      response = @app.call(env)
      status = response[0]
      response
    rescue StandardError => error
      # Test mode and unhandled failures may escape instead of becoming a response.
      exception = error
      raise
    ensure
      record_request(env, requested_at, started_at, status, exception)
    end
  end

  private

  # ----------------------------------------------------------------------------
  def record_request(env, requested_at, started_at, status, exception)
    request = ActionDispatch::Request.new(env)
    authorization = env["HTTP_AUTHORIZATION"]
    # Hash only a complete Bearer credential, never retain a usable secret/header.
    bearer = authorization.to_s.match(/\ABearer ([^\s,]+)\z/i)
    authentication_method = env["wayfinder.api_authentication_method"] || (authorization.nil? ? "anonymous" : "bearer")
    if exception
      # Map raised exceptions just as Rails would when rendering an error response.
      status = ActionDispatch::ExceptionWrapper.new(env["action_dispatch.backtrace_cleaner"], exception).status_code
    else
      exception = env["action_dispatch.exception"]
    end

    ip_resolution_exception_class = nil
    begin
      # Resolve proxy headers separately so spoof attempts cannot erase the audit row.
      remote_ip = request.remote_ip.to_s.first(255)
    rescue ActionDispatch::RemoteIp::IpSpoofAttackError => error
      remote_ip = nil
      ip_resolution_exception_class = error.class.name
    end

    # Use an allowlist: request bodies, queries, cookies and Authorization stay out.
    ApiRequestLog.create!(
      requested_at: requested_at,
      request_id: request.request_id.to_s.first(255),
      remote_ip: remote_ip,
      peer_ip: env["REMOTE_ADDR"].to_s.first(255),
      http_method: request.request_method.to_s.first(16),
      path: request.path.to_s.first(4096),
      status: status,
      duration_ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round(3),
      user_agent: request.user_agent.to_s.first(1024),
      authentication_method: authentication_method,
      token_fingerprint: bearer && Digest::SHA256.hexdigest(bearer[1]),
      exception_class: exception&.class&.name.to_s.presence,
      ip_resolution_exception_class: ip_resolution_exception_class,
      user_id: env["wayfinder.api_user_id"]
    )
  rescue StandardError => error
    # A logging outage must not turn a successful mutation into a failed response.
    # Exception messages can contain SQL values, so emit only the sanitized class.
    error_class = error.class.name.to_s.gsub(/[^A-Za-z0-9_:]/, "").first(255)
    begin
      Rails.logger.error("API request audit failed: #{error_class}")
    rescue StandardError
      # A simultaneous logger outage must not replace the original HTTP response.
      nil
    end
  end
end
