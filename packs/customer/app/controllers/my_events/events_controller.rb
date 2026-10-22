# 利用者の「わたしの出来事」（/events）: 自分の口座にかかわる出来事だけを、日本語で・図で見る（TODO の R の利用者版）。
# 一覧と生中継（index）、1件の中身とつながりの図（show）、タイムマシン（time_machine）。表示の部品は行員の画面と同じ packs/event_lens。
# 他人の口座・他人の出来事は「ない」ものとして 404。読むだけ。
# 利用者画面の土台（Netbank::ApplicationController。ログイン・ねこテーマ・お知らせ）をそのまま使う。
# 名前空間を Netbank:: にしないのは、メニューの「わたしの口座」の印（netbank の画面にいるか）と分けるため
module MyEvents
  class EventsController < Netbank::ApplicationController
    helper EventLens::EventsHelper

    LIMIT = 100
    # 付帯情報のうち利用者に見せるもの（二人承認の申請者・承認者、リクエストや接続元は行員の内部の情報）
    METADATA_KEYS = %i[actor timestamp valid_at correlation_id causation_id].freeze

    # 利用者の画面では、名前を出すのは本人だけ（行員は「銀行の行員」、ほかの利用者は「ほかのお客さま」）
    def self.names_for(customer)
      EventLens::Names.new(people: { "customer" => { customer.id.to_s => customer.name } })
    end

    def index
      @accounts = my_accounts.order(:number)
      @account = find_my_account(params[:account]) if params[:account].present?
      @kind = EventLens::Catalog::KINDS.key?(params[:kind]&.to_sym) ? params[:kind].to_sym : nil
      scope = @account ? EventScope.new([ @account.number ]) : event_scope
      types = EventLens::Catalog.types_of(@kind).map(&:name) if @kind
      @events = EventLens::EventIndex.new.events.reverse_each.lazy
                                     .select { scope.visible?(it) && (types.nil? || types.include?(it.event_type)) }
                                     .first(LIMIT)
    end

    def show
      @flow = EventLens::Flow.around(params[:id], only: event_scope)
      @event = @flow.seed
    rescue EventLens::Flow::NotFound
      raise ActiveRecord::RecordNotFound
    end

    def time_machine
      @accounts = my_accounts.order(:number)
      @account = params[:account].present? ? find_my_account(params[:account]) : @accounts.first
      @machine = EventLens::TimeMachine.new(@account.number, basis: params[:basis]) if @account
    end

    private

    # 生中継のジョブ（EventsLiveJob）が描くときはログイン中の人がいないので、見えるかどうかの確かめはしない（ジョブが確かめてから描く）
    def event_scope = (@event_scope ||= EventScope.new(current_customer.account_numbers) if current_customer)

    # 生中継のジョブが描くとき（ログイン中の人がいない）は、口座の名義だけを引く Names（人の名前はジョブが部品に渡す）
    def names = @names ||= current_customer ? self.class.names_for(current_customer) : EventLens::Names.new
    helper_method :names

    # event_lens の部品が使うリンク先。見られないもの（他人の出来事・他人の口座）にはリンクしない。レーン図は行員の画面だけ
    def lens_event_path(event_id)
      return event_path(event_id) unless event_scope

      event = Rails.configuration.event_store.read.event(event_id)
      event_path(event_id) if event_scope.visible?(event)
    rescue RubyEventStore::EventNotFound
      nil
    end

    def lens_lanes_path(stream:) = nil

    def lens_time_machine_path(account:)
      event_time_machine_path(account:) if event_scope.nil? || event_scope.account_numbers.include?(account.to_s)
    end
    helper_method :lens_event_path, :lens_lanes_path, :lens_time_machine_path
  end
end
