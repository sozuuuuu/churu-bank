require "test_helper"

# 行員と利用者は別のアカウント・別のログイン・別の Cookie。片方でログインしても、もう片方の画面には入れない
class StaffCustomerSeparationTest < ActionDispatch::IntegrationTest
  setup do
    @staff = create_staff
    @orca = create_customer(name: "オルカ")
    @orca_number = Banking::Bank.new(actor: "test").open_account(holder_name: "オルカ").account_number
    @orca.grant_account(@orca_number)
  end

  test "行員の Cookie では利用者の画面に入れない（利用者のログイン画面へ）" do
    sign_in_as_staff @staff

    [ root_path, account_path(@orca_number), notices_path, shop_root_path ].each do |path|
      get path
      assert_redirected_to new_customer_session_path, path
    end
  end

  test "利用者の Cookie では行員の画面に入れない（行員のログイン画面へ）。/res は 404" do
    sign_in_as_customer @orca

    [ admin_root_path, admin_account_path(@orca_number), notices_admin_notices_path, shop_admin_products_path ].each do |path|
      get path
      assert_redirected_to new_staff_session_path, path
    end
    get "/res"
    assert_response :not_found
  end

  test "利用者の画面には行員の画面へのリンクを出さない" do
    sign_in_as_customer @orca

    get root_path
    assert_response :success
    assert_select "a[href^='/admin']", count: 0
  end

  test "同じブラウザで両方にログインでき、ログアウトは片方だけ" do
    sign_in_as_staff @staff
    sign_in_as_customer @orca

    get root_path
    assert_response :success
    get admin_root_path
    assert_response :success

    delete customer_session_path
    get root_path
    assert_redirected_to new_customer_session_path
    get admin_root_path
    assert_response :success
  end

  test "行員の Cookie の値を利用者の Cookie の名前に入れても通らない（署名が Cookie の名前ごとに違う）" do
    sign_in_as_staff @staff
    cookies[:customer_session_id] = cookies[:staff_session_id]

    get root_path
    assert_redirected_to new_customer_session_path
  end

  test "id がたまたま同じでも、別の Cookie の署名では見つからない" do
    customer_session_id = create_customer_session_id(@orca)
    jar = ActionDispatch::TestRequest.create.cookie_jar
    jar.signed[:staff_session_id] = customer_session_id
    jar[:customer_session_id] = jar[:staff_session_id]

    assert_nil CustomerAuthentication.customer_from(jar)
    jar.signed[:customer_session_id] = customer_session_id
    assert_equal @orca, CustomerAuthentication.customer_from(jar)
  end
end
