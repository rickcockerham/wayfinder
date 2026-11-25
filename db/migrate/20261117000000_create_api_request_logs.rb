class CreateApiRequestLogs < ActiveRecord::Migration[7.1]
  # ----------------------------------------------------------------------------
  def change
    # Keep API diagnostics separate from application records and retain history.
    create_table :api_request_logs do |t|
      t.datetime :requested_at, precision: 6, null: false
      t.string :request_id, null: false
      t.string :remote_ip
      t.string :peer_ip
      t.string :http_method, limit: 16, null: false
      t.text :path, null: false
      t.integer :status, null: false
      t.decimal :duration_ms, precision: 12, scale: 3, null: false
      t.text :user_agent
      t.string :authentication_method, limit: 16, null: false
      t.string :token_fingerprint, limit: 64
      t.string :exception_class
      t.string :ip_resolution_exception_class
      # Preserve the observed identity even if that account is later removed.
      t.bigint :user_id
    end

    # Support time, identity and credential investigations without scanning bodies.
    add_index :api_request_logs, :requested_at
    add_index :api_request_logs, :request_id
    add_index :api_request_logs, [:user_id, :requested_at]
    add_index :api_request_logs, [:token_fingerprint, :requested_at]
  end
end
