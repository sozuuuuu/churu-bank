# Action Cable（Turbo のライブ更新）もログインしている人だけ。
# 購読できるストリームは、画面に埋め込まれた署名つきの名前（turbo_stream_from）で決まる
module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      set_current_user || reject_unauthorized_connection
    end

    private
      def set_current_user
        if session = Session.find_by(id: cookies.signed[:session_id])
          self.current_user = session.user
        end
      end
  end
end
