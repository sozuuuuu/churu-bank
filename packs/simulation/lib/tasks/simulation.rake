namespace :churu do
  desc "ねこ町の住民の暮らし（住民 1 匹 = Ractor 1 つ）を動かす係。行員の画面 /admin/town から起動・停止・速さを変える。START=1 ならすぐ動かす"
  task simulate: :environment do
    Simulation::Control.current.update!(running: true) if ENV["START"] == "1"
    Simulation::Runner.new.run
  end

  namespace :simulation do
    desc "ねこ町の住民（利用者と口座）・給料を払う口座・商店の在庫を用意する（何度流しても増えない。churu:simulate も最初にする）"
    task setup: :environment do
      Simulation::Roster.setup!
      puts "ねこ町: 住民 #{Simulation::ResidentStatus.count} 匹（#{Simulation::ResidentStatus.pluck(:name).join('・')}）"
    end

    desc "住民の財布を整える: KEEP（ふだんは 200）ちゅ〜るを超える分を「ねこ町の基金」へ振り込む（振込なので記録に残り、戻すこともできる）"
    task trim_wallets: :environment do
      moved = Simulation::Roster.trim_wallets!(keep: Integer(ENV.fetch("KEEP", Simulation::Roster::FIRST_DEPOSIT)))
      moved.each { |name, amount| puts "#{name}: #{amount} ちゅ〜るを基金へ" }
      puts "ねこ町: 整える分はありませんでした" if moved.empty?
    end
  end
end
