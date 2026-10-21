# 利用者の画面のライブ更新（Turbo の refresh）を受けるチャンネル。利用者としてつないだ接続だけが購読できる。
# ストリーム名の署名は利用者用の鍵なので、行員の画面に埋め込まれた名前（StaffStreamsChannel 用）は通らない。
# 配信はふつうに Turbo::StreamsChannel.broadcast_refresh_to(...) でよい（署名は購読のときだけ使う）
class CustomerStreamsChannel < Turbo::StreamsChannel
  class << self
    def verified_stream_name(signed_stream_name) = verifier.verified(signed_stream_name)

    def signed_stream_name(streamables) = verifier.generate(stream_name_from(streamables))

    private

    def verifier = Rails.application.message_verifier("customer_streams")
  end

  def subscribed
    stream_name = verified_stream_name_from_params if current_customer
    stream_name ? stream_from(stream_name) : reject
  end
end
