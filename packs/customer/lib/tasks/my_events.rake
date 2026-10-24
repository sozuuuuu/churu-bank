namespace :churu do
  namespace :my_events do
    desc "「わたしの出来事」の索引（my_event_entries）を、イベントストアの全部の出来事から作り直す"
    task rebuild: :environment do
      count = MyEvents::FeedEntry.rebuild!
      puts "わたしの出来事: #{count} 件の出来事から、索引 #{MyEvents::FeedEntry.count} 行を作りました"
    end
  end
end
