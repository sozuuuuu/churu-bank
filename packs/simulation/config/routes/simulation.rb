# ねこ町の住民の暮らし（packs/simulation）: /admin/town。Simulation::ApplicationController で行員だけに絞る
scope "admin/town", module: "simulation", as: "simulation" do
  get "/", to: "residents#index", as: :residents # 住民の様子
  resource :control, only: :update               # 起動・停止・速さ
end
