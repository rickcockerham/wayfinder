require "test_helper"
require "minitest/mock"
require "tmpdir"
require "json"
require "net/http"
require "openssl"

class ItemBlocksCliTest < ActionDispatch::IntegrationTest
  #-----------------------------------------------------------------------------
  setup do
    @saved_environment = %w[WAYFINDER_API_CONFIG WAYFINDER_API_TOKEN_SHA256 WAYFINDER_API_USER_ID].to_h { |key| [key,ENV[key]] }
    @saved_forgery = ActionController::Base.allow_forgery_protection
    @user = users(:default_user)
    @a,@b,@c = %w[A B C].map { |name| @user.items.create!(title: "CLI graph #{name}",category: categories(:default_category),mood: moods(:default_mood)) }
    @token = "e" * 64
    @directory = Dir.mktmpdir("wayfinder-blocker-cli-")
    @config = File.join(@directory,"api.json")
    File.write(@config,JSON.generate(token:@token),perm:0o600)
    ENV["WAYFINDER_API_CONFIG"] = @config
    ENV["WAYFINDER_API_TOKEN_SHA256"] = Digest::SHA256.hexdigest(@token)
    ENV["WAYFINDER_API_USER_ID"] = @user.id.to_s
    ActionController::Base.allow_forgery_protection = true
  end

  #-----------------------------------------------------------------------------
  teardown do
    @saved_environment.each { |key,value| value.nil? ? ENV.delete(key) : ENV[key]=value }
    ActionController::Base.allow_forgery_protection = @saved_forgery
    FileUtils.remove_entry(@directory)
  end

  #-----------------------------------------------------------------------------
  test "actual CLI adds reads and removes a native blocker without deleting items" do
    added = invoke_cli(["block",@a.id.to_s,@b.id.to_s])
    assert_equal 0, added[:status]
    edge = added[:body].fetch("item_block")
    assert_equal [@a.id,@b.id,true],edge.values_at("blocker_id","blocked_id","active")
    assert_not @b.reload.ready_now?(inventory_hash:{})
    assert_equal edge["id"],invoke_cli(["block",@a.id.to_s,@b.id.to_s])[:body]["item_block"]["id"]
    [ ["blockers",@b.id.to_s], ["blocks",@a.id.to_s] ].each do |arguments|
      result = invoke_cli(arguments)
      assert_equal 0,result[:status]
      assert_equal [edge["id"]],result[:body]["item_blocks"].map { |row| row["id"] }
    end
    removed = invoke_cli(["unblock",edge["id"].to_s])
    assert_equal 0,removed[:status]
    assert_equal edge["id"],removed[:body]["deleted"]
    assert @b.reload.ready_now?(inventory_hash:{})
    assert Item.exists?(@a.id)
    assert Item.exists?(@b.id)
    stale = invoke_cli(["unblock",edge["id"].to_s])
    assert_equal 1,stale[:status]
    assert_equal "not_found",stale[:body]["error"]
  end

  #-----------------------------------------------------------------------------
  test "actual CLI rejects cycles cross owner and wrong bearer without creating links" do
    invoke_cli(["block",@a.id.to_s,@b.id.to_s])
    invoke_cli(["block",@b.id.to_s,@c.id.to_s])
    cycle = invoke_cli(["block",@c.id.to_s,@a.id.to_s])
    assert_equal 1,cycle[:status]
    assert_equal "validation_failed",cycle[:body]["error"]
    other = User.create!(name:"CLI other blocker",access_key:"cli-other-blocker-test-only")
    foreign = other.items.create!(title:"Private",category:other.categories.create!(name:"Private"),mood:other.moods.create!(name:"Private"))
    denied = invoke_cli(["block",foreign.id.to_s,@a.id.to_s])
    assert_equal 1,denied[:status]
    assert_equal "not_found",denied[:body]["error"]
    File.write(@config,JSON.generate(token:"f"*64))
    denied = invoke_cli(["blockers",@b.id.to_s])
    assert_equal 1,denied[:status]
    assert_equal "unauthorized",denied[:body]["error"]
    assert_equal 2,@user.item_blocks.count
  end

  private

  #-----------------------------------------------------------------------------
  def invoke_cli(arguments)
    # Run the real executable and HTTP request objects through Rails instead of a socket.
    saved_arguments = ARGV.dup
    ARGV.replace(arguments)
    session = ActionDispatch::Integration::Session.new(Rails.application)
    session.host! "mywayfinder.app"
    session.https!
    http = Net::HTTP.new("example.invalid",443)
    transport = lambda do |request|
      session.process(request.method.downcase.to_sym,request.path,params:request.body,
        headers:{"CONTENT_TYPE"=>request["Content-Type"],"HTTP_ACCEPT"=>request["Accept"],"HTTP_AUTHORIZATION"=>request["Authorization"]})
      code = session.response.status.to_s
      response = Net::HTTPResponse::CODE_TO_OBJ.fetch(code).new("1.1",code,"Fixture")
      response.body = session.response.body
      response.instance_variable_set(:@read,true)
      response
    end
    status = 0
    stdout,stderr = capture_io do
      Net::HTTP.stub(:new,lambda { |host,port| assert_equal ["mywayfinder.app",443],[host,port];http }) do
        http.stub(:request,transport) do
          begin
            load Rails.root.join("bin/wayfinder-api")
          rescue SystemExit => error
            status = error.status
          end
        end
      end
    end
    assert http.use_ssl?
    assert_equal OpenSSL::SSL::VERIFY_PEER,http.verify_mode
    refute_includes stdout,@token
    refute_includes stderr,@token
    {status:status,body:JSON.parse(stdout),stderr:stderr}
  ensure
    ARGV.replace(saved_arguments)
  end
end
