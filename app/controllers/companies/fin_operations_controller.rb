class Companies::FinOperationsController < ApplicationController
  before_action :set_company, only: [:index, :create, :show, :edit, :new]

  def index
    affiliates = Affiliate.where(company_id: params[:company_id])
    records = Record.where(affiliate: affiliates)
    rc = RecordClient.where(record: records)
    subscriptions = Subscription.where(record_client: rc)
    @fin_operations = FinOperation.where("(
      (operation_type = 1 AND operation_object_id IN (?)) OR 
      (operation_type = 0 AND operation_object_id IN (?)) AND
      affiliate_id IN (?))", 
      subscriptions.all.select('id'), 
      Client.where(company: params[:company_id]).select('id'),
      affiliates.select('id'),
      ).order("operation_date DESC")
  end

  def show
    @fin_operation = FinOperation.find(params[:id])
    @responsible = User.find(@fin_operation.user_id)
    @affiliate = Affiliate.find(@fin_operation.affiliate_id)

    if @fin_operation.operation_type == 'payment_other'
      @subscription = Client.find(@fin_operation.operation_object_id)
    elsif @fin_operation.operation_type == 'payment_subscription'
      @subscription = Subscription.find(@fin_operation.operation_object_id)
      record_subscription = RecordClient.find(@subscription.record_client_id)
      @client_subscription = Client.find(record_subscription.client_id)
    end


    @history = History.new
    @history_subscription = History.where("
      object_log = 'fin_operation' AND object_id IN (?)",
                                          @fin_operation.id,
      ).order("created_at DESC")
  end

  # def new
  #   @fin_operation = FinOperation.new
  #   @affiliates = Affiliate.where(company_id: params[:company_id])
  # end

  def create
    @fin_operation = FinOperation.new(fin_operation_params)
    @fin_operation.user_id = current_user.id

    @fin_operation.operation_number = FinOperation.where(affiliate_id: @fin_operation.affiliate_id).last.nil? ? 0 : FinOperation.where(affiliate_id: @fin_operation.affiliate_id).last.operation_number 
    @fin_operation.operation_number = 1 + @fin_operation.operation_number.to_i
 
    if @fin_operation.operation_type = 1
      subscription = Subscription.find(@fin_operation.operation_object_id)
      @fin_operation.description = "Оплата абонемента на период от #{subscription.start_at.strftime("%d %B %Y")} до #{subscription.finish_at.strftime("%d %B %Y")}"
    end

    if @fin_operation.amount.to_i == 0
      redirect_to request.referer, notice: "Оплата не создана, необходимо указать сумму больше <span class=\"amount\">0.0 ₽</span>"      
    elsif @fin_operation.save
      redirect_to request.referer, notice: "Финансовая операция <a href=\"#{company_fin_operation_path(params[:company_id], @fin_operation.id)}\" class=\"link-style\" style=\"text-transform: lowercase;\">#{t('operation_type.' + @fin_operation.operation_type)}</a> на сумму <span class=\"amount\">#{@fin_operation.amount} ₽</span> произведена"
    else
      render :new
    end

  end

  private
    def fin_operation_params
      params.require(:fin_operation).permit(:amount, :operation_date, :operation_type, :operation_object_id, :is_active, :description, :description_cancellation, :affiliate_id)
    end
    def set_company
      @current_company = Company.find(params[:company_id])
      render html: "Sorry, but the company with id = #{@current_company} is not yours" unless @current_company.user_id == current_user.id
    end
end
