# イベントビューア（/admin/events）の土台。行員としてログインしていなければ、行員のログイン画面へ（packs/staff_identity）。
# 読むだけなので Banking::Bank などの入口は使わない。表示の部品は packs/event_lens
module EventViewer
  class ApplicationController < ::ApplicationController
    include StaffAuthentication
    helper Ui::FormatHelper
    helper Ui::ThemeHelper # 線画のアイコン（icon）
    helper EventLens::EventsHelper

    layout "event_viewer"

    # 行員の画面では、行員も利用者も名前で出す
    def self.names
      EventLens::Names.new(people: {
        "staff" => Staff.pluck(:id, :name).to_h.transform_keys(&:to_s),
        "customer" => Customer.pluck(:id, :name).to_h.transform_keys(&:to_s)
      })
    end

    private

    def names = @names ||= self.class.names
    helper_method :names

    # event_lens の部品が使うリンク先（行員はどれでも見られる）
    def lens_event_path(event_id) = event_viewer_event_path(event_id)
    def lens_lanes_path(stream:) = event_viewer_lanes_path(stream:)
    def lens_time_machine_path(account:) = event_viewer_time_machine_path(account:)
    helper_method :lens_event_path, :lens_lanes_path, :lens_time_machine_path
  end
end
