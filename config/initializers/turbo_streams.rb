# 素の Turbo::StreamsChannel（turbo_stream_from）では購読させない。ライブ更新の購読は、行員の画面は
# StaffStreamsChannel（staff_stream_from）、利用者の画面は CustomerStreamsChannel（customer_stream_from）だけ。
# 署名の鍵もチャンネルごとに違うので、片方の画面に埋め込まれたストリーム名でもう片方のチャンネルは購読できない。
# 配信（broadcast_refresh_to）はどちらも Turbo::StreamsChannel のままでよい
module RejectPlainTurboStreams
  def subscribed = reject
end

Rails.application.config.to_prepare do
  Turbo::StreamsChannel.prepend(RejectPlainTurboStreams) unless Turbo::StreamsChannel <= RejectPlainTurboStreams
end
