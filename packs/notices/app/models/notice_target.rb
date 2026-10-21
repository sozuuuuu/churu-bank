# お知らせの対象に選ばれた利用者（Notice#audience が "selected" のとき）
class NoticeTarget < ApplicationRecord
  belongs_to :notice
  belongs_to :user
end
