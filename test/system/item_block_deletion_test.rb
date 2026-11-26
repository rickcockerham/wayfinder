require "application_system_test_case"

class ItemBlockDeletionTest < ApplicationSystemTestCase
  driven_by :selenium,using: :headless_chrome,screen_size:[1200,900]

  #-----------------------------------------------------------------------------
  setup do
    @user = users(:default_user)
    @a,@project,@b,@child,@other = %w[Prerequisite Project Dependent Child Other].map do |name|
      @user.items.create!(title:"Delete graph fixture #{name}",category:categories(:default_category),mood:moods(:default_mood))
    end
    @child.update!(parent:@project)
    @incoming = @user.item_blocks.create!(blocker:@a,blocked:@project)
    @outgoing = @user.item_blocks.create!(blocker:@project,blocked:@b)
    @retained = @user.item_blocks.create!(blocker:@child,blocked:@other)
    visit login_url
    fill_in "key",with:@user.access_key
    click_on "Sign in"
    assert_current_path root_path
    visit item_url(@project)
    assert_selector "h1",text:@project.title
  end

  #-----------------------------------------------------------------------------
  def teardown
    # Capybara 3.40's wildcard storage reset is incompatible with Chrome 158.
    Capybara.current_session.driver.quit
    super
  end

  #-----------------------------------------------------------------------------
  test "actual project destroy confirms and removes both link directions but not survivors" do
    dismiss_confirm("Delete this item?") { click_on "Destroy" }
    assert Item.exists?(@project.id)
    assert ItemBlock.exists?(@incoming.id)
    assert ItemBlock.exists?(@outgoing.id)
    accept_confirm("Delete this item?") { click_on "Destroy" }
    assert_current_path items_path
    assert_no_text @project.title
    assert_not Item.exists?(@project.id)
    assert_not ItemBlock.exists?(@incoming.id)
    assert_not ItemBlock.exists?(@outgoing.id)
    assert ItemBlock.exists?(@retained.id)
    [@a,@b,@child,@other].each { |item| assert Item.exists?(item.id) }
    assert_nil @child.reload.parent_id
  end
end
