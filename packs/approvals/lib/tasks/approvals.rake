namespace :approvals do
  desc "二人承認の読み取りモデル（approval_requests）をイベントから作り直す"
  task rebuild_projections: :environment do
    Approvals::Projection.rebuild
    puts "approval_requests: #{ApprovalRequest.count} 件"
  end
end
