# Load explicitly because middleware is built before regular application autoloads.
require Rails.root.join("lib/api_request_audit")

# RequestId and RemoteIp have already enriched the environment at this position.
# Wrap Rails logging too: its remote_ip lookup can reject spoofed proxy headers.
# ShowExceptions remains inside this wrapper so returned HTTP statuses are recorded.
Rails.application.config.middleware.insert_after ActionDispatch::RemoteIp, ApiRequestAudit
