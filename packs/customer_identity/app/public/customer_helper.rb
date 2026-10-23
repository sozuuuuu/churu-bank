# 利用者の画面のビューで使うもの（CustomerAuthentication を include すると入る）
module CustomerHelper
  # packs/ui の layouts/application のヘッダーに、利用者の名前とログアウトを入れる。
  # 利用者の画面のレイアウトで render template: "layouts/cat" より前に1回呼ぶ
  def customer_header
    content_for :home_path, root_path
    content_for :entrance, link_to("行員の入り口", admin_root_path, class: "entrance")
    return unless current_customer

    content_for :account do
      safe_join([ tag.span(current_customer.name, class: "muted"),
                  button_to("ログアウト", customer_session_path, method: :delete, class: "link") ])
    end
    nil
  end

  # turbo_stream_from の利用者用。CustomerStreamsChannel で、利用者用の鍵で署名したストリーム名を埋め込む
  # （行員の接続の画面のストリーム名とも互換がない）
  def customer_stream_from(*streamables, **attributes)
    raise ArgumentError, "streamables can't be blank" unless streamables.any?(&:present?)

    tag.turbo_cable_stream_source(**attributes, channel: "CustomerStreamsChannel",
                                                "signed-stream-name": CustomerStreamsChannel.signed_stream_name(streamables))
  end
end
