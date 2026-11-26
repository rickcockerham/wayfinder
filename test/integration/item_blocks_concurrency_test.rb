require "test_helper"
require "digest"
require "timeout"

class ItemBlocksConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false
  self.fixture_table_names = []

  #-----------------------------------------------------------------------------
  test "opposing API and web additions cannot concurrently create a cycle" do
    # Committed fixtures let independent request connections contend on the real owner lock.
    user = User.create!(name:"Concurrent graph fixture",access_key:"concurrent-graph-fixture-only")
    category = user.categories.create!(name:"Concurrent graph")
    mood = user.moods.create!(name:"Concurrent graph")
    a,b = %w[A B].map { |name| user.items.create!(title:"Concurrent #{name}",category:category,mood:mood) }
    previous = %w[WAYFINDER_API_TOKEN_SHA256 WAYFINDER_API_USER_ID].to_h { |key| [key,ENV[key]] }
    token = "1" * 64
    ENV["WAYFINDER_API_TOKEN_SHA256"] = Digest::SHA256.hexdigest(token)
    ENV["WAYFINDER_API_USER_ID"] = user.id.to_s
    api = ActionDispatch::Integration::Session.new(Rails.application)
    web = ActionDispatch::Integration::Session.new(Rails.application)
    web.post "/login",params:{key:user.access_key}
    ready = Queue.new
    start = Queue.new
    results = Queue.new
    threads = [
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          start.pop
          api.post "/api/item_blocks",params:{item_block:{blocker_id:a.id,blocked_id:b.id}},headers:{"Authorization"=>"Bearer #{token}"},as: :json
          results << api.response.status
        end
      end,
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          start.pop
          web.post "/item_blocks",params:{item_block:{blocker_id:b.id,blocked_id:a.id}}
          results << web.response.status
        end
      end
    ]
    Timeout.timeout(15) do
      2.times { ready.pop }
      2.times { start << true }
      threads.each(&:value)
    end
    statuses = 2.times.map { results.pop }
    assert_equal 1,statuses.count { |status| [201,302].include?(status) }
    assert_equal 1,statuses.count(422)
    assert_equal 1,user.item_blocks.count
  ensure
    threads&.each { |thread| thread.kill if thread.alive? }
    previous&.each { |key,value| value.nil? ? ENV.delete(key) : ENV[key]=value }
    if user&.persisted?
      user.item_blocks.destroy_all
      user.items.destroy_all
      user.categories.destroy_all
      user.moods.destroy_all
      user.destroy!
    end
  end
end
