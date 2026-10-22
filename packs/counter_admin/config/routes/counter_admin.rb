# 窓口の列とチャット（行員、packs/counter_admin）。窓口（出金依頼 /admin/counter、packs/admin）の隣に置く。
# 「次の方」「終わる」はふつうの POST。チャットの発言は Action Cable（Counter::ChatChannel）
scope "admin/counter/queue", module: :counter_admin, as: :counter_admin do
  get "/", to: "queues#show", as: :queue        # 列（お待ち・対応中・最近の終わり）
  post "call", to: "calls#create", as: :call    # 次の方を呼ぶ
  resources :tickets, only: :show do            # その札のチャット（終わったものは記録として見るだけ）
    resource :finish, only: :create             # 終わる
  end
end
