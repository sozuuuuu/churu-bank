# 行員の画面のライブ更新（Turbo の refresh）を受けるチャンネル。行員としてつないだ接続だけが購読できる。
# ストリーム名の署名は行員用の鍵なので、利用者の画面に埋め込まれた名前（CustomerStreamsChannel 用）は通らない。
# 配信はふつうに Turbo::StreamsChannel.broadcast_refresh_to(...) でよい（署名は購読のときだけ使う）
class StaffStreamsChannel < Turbo::StreamsChannel
  class << self
    def verified_stream_name(signed_stream_name) = verifier.verified(signed_stream_name)

    def signed_stream_name(streamables) = verifier.generate(stream_name_from(streamables))

    private

    def verifier = Rails.application.message_verifier("staff_streams")
  end

  def subscribed
    stream_name = verified_stream_name_from_params if current_staff
    stream_name ? stream_from(stream_name) : reject
  end
end
