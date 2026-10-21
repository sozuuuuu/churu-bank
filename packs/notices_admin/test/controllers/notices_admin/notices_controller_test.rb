require "test_helper"

class NoticesAdmin::NoticesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @staff = create_staff
    @orca = create_customer(name: "オルカ")
  end

  test "利用者のログインではお知らせを作れない（行員のログイン画面へ）" do
    sign_in_as_customer @orca
    notice = Notices::Board.new(actor: "test").post(kind: "info", title: "みんなへ")

    get notices_admin_notices_path
    assert_redirected_to new_staff_session_path
    assert_no_difference "Notice.count" do
      post notices_admin_notices_path, params: { notice: { kind: "info", title: "いたずら", audience: "everyone", starts_at: Time.current } }
    end
    assert_redirected_to new_staff_session_path
    patch notices_admin_notice_path(notice), params: { notice: { title: "書きかえ" } }
    assert_redirected_to new_staff_session_path
    post notices_admin_notice_closing_path(notice)
    assert_redirected_to new_staff_session_path
    assert_equal "みんなへ", notice.reload.title
    assert_not notice.ended?
  end

  test "行員はお知らせを出せて、利用者画面にライブで知らせる" do
    sign_in_as_staff @staff

    assert_enqueued_jobs 1 do # 利用者画面への refresh（Notices::RefreshJob。notices の非公開なので数だけ見る）
      post notices_admin_notices_path, params: { notice: {
        kind: "maintenance", title: "メンテナンスのお知らせ", body: "少し止まります", important: "1",
        starts_at: Time.current.strftime("%Y-%m-%dT%H:%M"), ends_at: "", audience: "everyone", target_customer_ids: [ "" ]
      } }
    end

    assert_redirected_to notices_admin_notices_path
    notice = Notice.find_by!(title: "メンテナンスのお知らせ")
    assert notice.important?
    assert_nil notice.ends_at
    assert_equal @staff.actor, notice.posted_by
  end

  test "選んだ利用者に出す。選ばなければ出せない" do
    sign_in_as_staff @staff
    params = { kind: "request", title: "オルカさんへ", starts_at: Time.current, audience: "selected" }

    post notices_admin_notices_path, params: { notice: params.merge(target_customer_ids: [ "" ]) }
    assert_response :unprocessable_entity
    assert_match "対象の利用者を選んでください", response.body

    post notices_admin_notices_path, params: { notice: params.merge(target_customer_ids: [ "", @orca.id ]) }
    assert_equal [ @orca ], Notice.find_by!(title: "オルカさんへ").target_customers
  end

  test "行員は直せて、掲載を終えられる" do
    sign_in_as_staff @staff
    notice = Notices::Board.new(actor: "test").post(kind: "info", title: "まちがい")

    get edit_notices_admin_notice_path(notice)
    assert_response :success
    patch notices_admin_notice_path(notice), params: { notice: { title: "なおした" } }
    assert_redirected_to notices_admin_notices_path
    assert_equal "なおした", notice.reload.title

    post notices_admin_notice_closing_path(notice)
    assert_redirected_to notices_admin_notices_path
    assert notice.reload.ended?
    get notices_admin_notices_path
    assert_match "掲載終了", response.body
  end

  test "管理画面のメニューからお知らせへ行ける" do
    sign_in_as_staff @staff
    get admin_accounts_path
    assert_select "a[href='#{notices_admin_notices_path}']", text: "お知らせ"
  end
end
