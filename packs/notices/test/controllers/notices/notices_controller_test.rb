require "test_helper"

class Notices::NoticesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @board = Notices::Board.new(actor: "test")
    @orca = create_user(name: "オルカ")
    @mike = create_user(name: "ミケ")
    sign_in_as @orca
  end

  test "利用者画面に、ねこの吹き出しと未読のバッジが出て、ライブ更新を購読している" do
    @board.post(kind: "request", title: "住所変更のお届けをお願いします", important: true)

    get root_path

    assert_response :success
    assert_select "#notice-board .notice-bubble", text: /住所変更のお届けをお願いします/
    assert_select "#notice-nav .notice-badge", text: "1"
    assert_select "#notice-board[data-controller='notices--inbox']"
    assert_match "notices/notices", response.body # お知らせの CSS
    assert_operator response.body.scan("turbo-cable-stream-source").size, :>=, 2 # 全員向けと自分向け
  end

  test "お知らせがなければ吹き出しは隠れていて、バッジも出ない" do
    get root_path

    assert_select "#notice-board[hidden]"
    assert_select ".notice-badge", count: 0
  end

  test "開くと既読になって、バッジが減る" do
    notice = @board.post(kind: "info", title: "ジンジベルお迎え準備中", body: "準備中です")

    get notice_path(notice)

    assert_response :success
    assert_match "準備中です", response.body
    assert NoticeReceipt.find_by(notice:, user: @orca).read_at
    get root_path
    assert_select ".notice-badge", count: 0
    assert_select "#notice-board[hidden]" # ふつうのものは、読んだら吹き出しから消える
  end

  test "ホバーでの先読み（Turbo の prefetch）では既読にしない。リンク側でも先読みを止めている" do
    notice = @board.post(kind: "info", title: "まだ読んでない")

    get root_path
    assert_select "#notice-board[data-turbo-prefetch='false']"
    get notice_path(notice), headers: { "X-Sec-Purpose" => "prefetch" }

    assert_response :success
    assert_not NoticeReceipt.exists?(notice:, user: @orca)
  end

  test "重要なものは読んでも吹き出しに残り、閉じたら消える" do
    notice = @board.post(kind: "request", title: "だいじ", important: true)
    get notice_path(notice)
    get root_path
    assert_select "#notice-board .notice-bubble", text: /だいじ/

    post notice_dismissal_path(notice), headers: { "Referer" => root_url }

    assert_redirected_to root_url
    get root_path
    assert_select "#notice-board[hidden]"
  end

  test "一覧には自分が対象で掲載中のものだけ" do
    @board.post(kind: "info", title: "みんなへ")
    @board.post(kind: "info", title: "ミケさんへ", users: [ @mike ])
    @board.post(kind: "info", title: "あしたから", starts_at: 1.day.from_now)

    get notices_path

    assert_response :success
    assert_match "みんなへ", response.body
    assert_no_match "ミケさんへ", response.body
    assert_no_match "あしたから", response.body
  end

  test "対象外・期間外のお知らせは開くのも閉じるのも 404" do
    for_mike = @board.post(kind: "info", title: "ミケさんへ", users: [ @mike ])
    ended = @board.post(kind: "info", title: "おわり", starts_at: 2.days.ago, ends_at: 1.day.ago)

    get notice_path(for_mike)
    assert_response :not_found
    get notice_path(ended)
    assert_response :not_found
    post notice_dismissal_path(for_mike)
    assert_response :not_found
    assert_not NoticeReceipt.exists?(user: @orca)
  end

  test "ログインしていなければログイン画面へ" do
    sign_out
    get notices_path
    assert_redirected_to new_session_path
  end
end
