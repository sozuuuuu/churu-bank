namespace :churu do
  desc "読み取りモデル（accounts / ledger_entries / transfers）をイベントストアから作り直す"
  task rebuild_projections: :environment do
    count = Projections::Rebuild.new.call
    puts "#{count} 件のイベントから読み取りモデルを作り直しました"
  end
end
