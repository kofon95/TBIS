class HomeController < ApplicationController
  layout 'application'

  def index
  end
  def search_result
    @search_request = params[:request]
    clients_company = Client.where company_id: @current_company.id

    if @search_request.size == 1 and @search_request[0].size >= 1 or @search_request[1].size == 0
      @products = clients_company.where("LOWER(last_name) LIKE LOWER('#{@search_request[0]}%')")
    elsif @search_request.size == 2 and @search_request[1].size >= 1 or @search_request[2].size == 0
      @products = clients_company.where("LOWER(last_name) LIKE LOWER('%#{@search_request[0]}%') AND LOWER(first_name) LIKE LOWER('#{@search_request[1]}%')")
    elsif @search_request.size == 3 and @search_request[2].size >= 1
      @products = clients_company.where("LOWER(last_name) LIKE LOWER('#{@search_request[0]}%') AND LOWER(first_name) LIKE LOWER('#{@search_request[1]}%') AND LOWER(patronymic) LIKE LOWER('#{@search_request[2]}%')")
    else
      @products = ""
    end

    render layout: false
  end

  def account
    @email = params[:request]
    @user_accounts = User.find_by(email: @email)

    render layout: false
  end

  def add_subscriptions_automatically
    today = Date.today
    date_of_last_day_of_previous_month = today - today.day.days
    sql = <<SQL
select rc.*, c.archive, r.total_visits, r.finished_at from (
  SELECT row_number() over(partition by record_client_id order by finish_at desc) rn, *
  FROM "subscriptions"
  WHERE is_active = true
) s inner join records_clients rc on s.record_client_id = rc.id
    inner join records r on rc.record_id = r.id
    inner join clients c on rc.client_id = c.id
where rn = 1 and finish_at = '#{date_of_last_day_of_previous_month}' and rc.is_active = true 
      and r.finished_at > '#{Date.today}' and c.archive = false
SQL

    start_at = date_of_last_day_of_previous_month + 1.day
    finish_at = date_of_last_day_of_previous_month + Time.days_in_month(today.month).days
    rows = ActiveRecord::Base.connection.select_all(sql).to_hash

    rows.each do |rc|

      price_service = RecordService.where(record_id: rc['record_id']).sum(:money_for_abon).to_f
      price_correction = Discount.where(record_client_id: rc['id']).sum(:value)
      price = price_service + price_correction

      subs = Subscription.new({
        start_at: start_at,
        finish_at: finish_at,
        visits: rc['total_visits'],
        record_client_id: rc['id'],
        price: price,
      })
      subs.save
      History.create({
        object_log: 'subscription', 
        object_id: subs.id, 
        type_history: 'auto_create', 
        note: 'Автоматическое создание абонемента', 
        user_id: current_user.id
      })
    end
    render plain: "#{rows.size} subscriptions were created"
  end
end
