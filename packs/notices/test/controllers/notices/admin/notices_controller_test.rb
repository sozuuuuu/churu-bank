require "test_helper"

class Notices::Admin::NoticesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @staff = create_user(name: "行員", admin: true)
    @orca = create_user(name: "オルカ")
  end

  test "利用者はお知らせを作れない（管理の画面もあることを見せない）" do
    sign_in_as @orca
    notice = Notices::Board.new(actor: "test").post(kind: "info", title: "みんなへ")

    get notices_admin_notices_path
    assert_response :not_found
    assert_no_difference "Notice.count" do
      post notices_admin_notices_path, params: { notice: { kind: "info", title: "いたずら", audience: "everyone", starts_at: Time.current } }
    end
    assert_response :not_found
    patch notices_admin_notice_path(notice), params: { notice: { title: "書きかえ" } }
    assert_response :not_found
    post notices_admin_notice_closing_path(notice)
    assert_response :not_found
    assert_equal "みんなへ", notice.reload.title
    assert_not notice.ended?
  end

  test "行員はお知らせを出せて、利用者画面にライブで知らせる" do
    sign_in_as @staff

    assert_enqueued_with(job: Notices::RefreshJob) do
      post notices_admin_notices_path, params: { notice: {
        kind: "maintenance", title: "メンテナンスのお知らせ", body: "少し止まります", important: "1",
        starts_at: Time.current.strftime("%Y-%m-%dT%H:%M"), ends_at: "", audience: "everyone", target_user_ids: [ "" ]
      } }
    end

    assert_redirected_to notices_admin_notices_path
    notice = Notice.find_by!(title: "メンテナンスのお知らせ")
    assert notice.important?
    assert_nil notice.ends_at
    assert_equal "admin:#{@staff.email_address}", notice.posted_by
  end

  test "選んだ利用者に出す。選ばなければ出せない" do
    sign_in_as @staff
    params = { kind: "request", title: "オルカさんへ", starts_at: Time.current, audience: "selected" }

    post notices_admin_notices_path, params: { notice: params.merge(target_user_ids: [ "" ]) }
    assert_response :unprocessable_entity
    assert_match "対象の利用者を選んでください", response.body

    post notices_admin_notices_path, params: { notice: params.merge(target_user_ids: [ "", @orca.id ]) }
    assert_equal [ @orca ], Notice.find_by!(title: "オルカさんへ").target_users
  end

  test "行員は直せて、掲載を終えられる" do
    sign_in_as @staff
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
    sign_in_as @staff
    get admin_accounts_path
    assert_select "a[href='#{notices_admin_notices_path}']", text: "お知らせ"
  end
end
