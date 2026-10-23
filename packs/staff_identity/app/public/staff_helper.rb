# 行員の画面のビューで使うもの（StaffAuthentication を include すると入る）
module StaffHelper
  # packs/ui の layouts/application のヘッダーに、行員の名前とログアウト、ロゴのリンク先（管理画面）を入れる。
  # 行員の画面のレイアウトで render template: "layouts/application" より前に1回呼ぶ
  def staff_header
    content_for :home_path, admin_root_path
    content_for :entrance, link_to("お客さまの入り口", root_path, class: "entrance")
    return unless current_staff

    content_for :account do
      safe_join([ tag.span(current_staff.name, class: "muted"),
                  button_to("ログアウト", staff_session_path, method: :delete, class: "link") ])
    end
    nil
  end

  # turbo_stream_from の行員用。StaffStreamsChannel で、行員用の鍵で署名したストリーム名を埋め込む
  # （利用者の接続からは購読できず、利用者の画面のストリーム名とも互換がない）
  def staff_stream_from(*streamables, **attributes)
    raise ArgumentError, "streamables can't be blank" unless streamables.any?(&:present?)

    tag.turbo_cable_stream_source(**attributes, channel: "StaffStreamsChannel",
                                                "signed-stream-name": StaffStreamsChannel.signed_stream_name(streamables))
  end
end
