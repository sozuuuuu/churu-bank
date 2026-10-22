# 窓口の整理券と窓口チャット（packs/counter）。ルートの config/routes.rb の `draw :counter` で読み込まれる。
# 利用者: /counter（いまの札。取る = POST、返す = DELETE）。チャットは /counter の中で、Action Cable でやりとりする。
# 行員の /admin/counter/queue は packs/counter_admin
scope module: :counter do
  resource :counter, only: %i[show create destroy], controller: "tickets"
end
