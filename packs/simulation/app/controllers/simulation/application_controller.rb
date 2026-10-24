# 住民の様子（/admin/town）の土台。行員としてログインしていなければ、行員のログイン画面へ（packs/staff_identity）。
# 見た目は管理画面と同じ（packs/admin の layouts/admin をテンプレート名で使う）
module Simulation
  class ApplicationController < ::ApplicationController
    include StaffAuthentication
    helper Ui::FormatHelper
    helper Ui::ThemeHelper # ねこの顔（cat）
    helper PixelPetHelper # 住民のドット絵
    helper TownMapHelper # 町の地図（RPG のフィールド）

    layout "admin"
  end
end
