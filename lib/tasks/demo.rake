namespace :churu do
  desc "イベントビューア（/admin/events）で眺めるデモの出来事を起こす（振込・お買いもの・出金依頼・二人承認など。db:seed のあとで）"
  task demo_events: :environment do
    load Rails.root.join("db/demo_events.rb")
  end
end
