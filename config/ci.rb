# Run using bin/ci

CI.run do
  step "Setup", "bin/setup --skip-server"

  step "Style: Ruby", "bin/rubocop"
  step "Packages: packwerk", "bin/packwerk validate && bin/packwerk check"

  step "Security: Gem audit", "bin/bundler-audit"
  step "Security: Importmap vulnerability audit", "bin/importmap audit"
  step "Security: Brakeman code analysis", "bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error"
  step "Tests: Rails", "bin/test"
  step "Tests: Seeds", "env RAILS_ENV=test bin/rails db:seed:replant"
  # seed が流れることを確かめたら、試験用の DB を空に戻す（残すと、あとで単独で流す試験が seed の商品とぶつかる）。
  # replant の中で db:truncate_all がもう動いているので、同じ rake の呼び出しに並べると Rake は2回目を動かさない。だから別の段にする
  step "Cleanup: test DB", "env RAILS_ENV=test bin/rails db:truncate_all"

  # Optional: Run system tests
  # step "Tests: System", "bin/rails test:system"

  # Optional: set a green GitHub commit status to unblock PR merge.
  # Requires the `gh` CLI and `gh extension install basecamp/gh-signoff`.
  # if success?
  #   step "Signoff: All systems go. Ready for merge and deploy.", "gh signoff"
  # else
  #   failure "Signoff: CI failed. Do not merge or deploy.", "Fix the issues and try again."
  # end
end
