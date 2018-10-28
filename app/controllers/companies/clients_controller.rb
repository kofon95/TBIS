class Companies::ClientsController < ApplicationController
  before_action :ensure_current_user, :ensure_company_owner_role, only: [:index, :new, :edit, :update, :destroy]
  before_action :ensure_user_has_company
  before_action :set_s3_direct_post, only: [:new, :edit]
  before_action :confirm_actions, only: [:create, :update, :destroy, :archive, :role_employee, :role_client, :new, :edit]
  before_action :set_record_client
  before_action :set_client, only: [:show, :edit, :update, :destroy, :archive]

  # GET /clients
  # GET /clients.json

  def index
    @people_company = Client.where(company: @current_company.id)
    @people_clients = @people_company.where("(role & #{Client::Role::CLIENT}) != 0")
    @no_archive_clients = @people_clients.where(archive: false)
    @archive_clients = @people_clients.where(archive: true)
    @current_clients = @no_archive_clients.where(id: 
      RecordClient.where(is_active: :true, record_id: 
        @current_record.select('id')).select('client_id'))

    unpaid_subscriptions = Subscription.find_by_sql("
      SELECT subscriptions.id
      FROM subscriptions
      WHERE subscriptions.id NOT IN (
        SELECT operation_object_id
        FROM (
          SELECT operation_object_id, sum(amount) as total_amount
          FROM fin_operations
          WHERE operation_type = 1 AND is_active = true
          GROUP BY operation_object_id, operation_type)
          AS results
        WHERE total_amount >= price)
      AND subscriptions.is_active = true
      AND NOT price = 0
    ")
    
    @clients_debtors = @people_clients.where(id: 
      RecordClient.where(id: 
        Subscription.where(id: 
          unpaid_subscriptions).select('record_client_id')).
      select('client_id'))

    @all_people = @people_clients
    @show_in_view = [@current_clients, @clients_debtors, @all_people, @archive_clients]
  end

  # GET /clients/1
  # GET /clients/1.json
  def show
    unless @client.present?
      return redirect_to company_clients_url, notice: "В компании нет такого человека"
    end
    @discount = Discount.new
    @subscription = Subscription.new
    @fin_operation = FinOperation.new
    @work = Work.new
    @salary = Work.new
    @work_salary = WorkSalary.new
    @new_record_client = RecordClient.new

    @records_client = RecordClient.where(client_id: params[:id], id: @current_record_client)
    
    completed_records = @current_record.where("finished_at < ?", Date.today)

    current_record = @current_record.where.not(id: completed_records)

    @no_records_client = current_record.where.not(id: @records_client.where(client_id: @client.id, is_active: :true).select('record_id'))

    @unpaid_subscriptions = Subscription.find_by_sql("
      SELECT subscriptions.*
      FROM subscriptions
      WHERE subscriptions.id NOT IN (
        SELECT operation_object_id
        FROM (
         SELECT operation_object_id, sum(amount) as total_amount
         FROM fin_operations
         WHERE operation_type = 1 AND is_active = true
         GROUP BY operation_object_id, operation_type
        ) AS results
        WHERE total_amount >= price) 
      AND subscriptions.is_active = true 
      AND subscriptions.record_client_id IN (
        SELECT  records_clients.id
        FROM records_clients 
        WHERE records_clients.client_id = #{params[:id]})
    ")

    @discounts = Discount.where(record_client: @records_client)

    @clients = Client.where(archive: false, company_id: @current_company.id)

    subscriptions_client = Subscription.where(record_client: @records_client)
    @fin_operations_client = FinOperation.where("(
      (operation_type = 1 AND operation_object_id IN (?)) 
      OR (operation_type = 0 AND operation_object_id = (?))
      AND affiliate_id IN (?)
      )", 
      subscriptions_client.all.select('id'), 
      @client.id,
      @current_affiliates.select(:id)
    ).order("operation_date DESC")

    @payments_subscriptions = FinOperation.where(" is_active = true AND
                operation_type = 1 AND operation_object_id IN (?)", 
                subscriptions_client.where(is_active: true).select('id'),
                ).order("operation_date DESC")
    @debt_for_services =  subscriptions_client.where(is_active: true).sum(:price) - @payments_subscriptions.sum(:amount)


    @blocks_clients = InfoBlock.where(company_id: @current_company.id, model_object: 'clients')
    @field_templates_clients = FieldTemplate.where(block_id: @blocks_clients).order("id")

    @works_client = Work.where people_id: @client.id
  end

  # GET /clients/new
  def new
    @client = Client.new company_id: @current_company.id, role: (Client::Role::CLIENT).to_s(2).to_i
    @new_block = InfoBlock.new
    @new_template_field = FieldTemplate.new
    @blocks_clients = InfoBlock.where(company_id: @current_company.id, model_object: 'clients')
    @field_templates_clients = FieldTemplate.where(block_id: @blocks_clients).order("id")
    @new_field_data = FieldDatum.new
    1.times { @client.field_data.build }
  end

  # GET /clients/1/edit
  def edit
    @client_new = Client.new company_id: @current_company.id
    @new_block = InfoBlock.new
    @new_template_field = FieldTemplate.new
    @blocks_clients = InfoBlock.where(company_id: @current_company.id, model_object: 'clients')
    @field_templates_clients = FieldTemplate.where(block_id: @blocks_clients).order("id")
    @new_field_data = FieldDatum.new 
    # 1.times { @client.field_data.build }
  end

  # POST /clients
  # POST /clients.json
  def create
    prms = client_params
    @client = Client.new(prms)

    @client.role = (Client::Role::CLIENT).to_s(2).to_i

    respond_to do |format|
      if @client.save
        email = params[:client][:email]

        account = User.find_by(email: email)
        if account.present?
          @client.update_attribute(:user_id, account.id)
          unless account.people_id.present?
            account.update_attribute(:people_id, @client.id)
          end
        end

        format.html { redirect_to [@client.company, @client], notice: t('client.created') }
        format.json { render :show, status: :created }
      else
        format.html { ensure_current_user; set_s3_direct_post; render :new } #   redirect_to request.referer
        format.json { render json: @client.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /clients/1
  # PATCH/PUT /clients/1.json
  def update

    respond_to do |format|
      if @client.update(client_params)
        email = params[:client][:email]

        account = User.find_by(email: email)
        if account.present?
          @client.update_attribute(:user_id, account.id)
          unless account.people_id.present?
            account.update_attribute(:people_id, @client.id)
          end
        end
        
        format.html { redirect_to [@client.company, @client], notice: t('client.updated') }
        format.json { render :show, status: :ok, location: @client }
      else
        format.html { render :edit }
        format.json { render json: @client.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /clients/1
  # DELETE /clients/1.json
  def destroy 
    @client.destroy
    respond_to do |format|
      format.html { redirect_to company_clients_url, notice: t('client.destroyed') }
      format.json { head :no_content }
    end
  end

  def archive 
    @client.archive = params[:archive_status] == '1'
    @client.save!
    respond_to do |format|
      format.html { redirect_to company_client_path(@current_company.id, params[:id]) }
      format.json { render :show, status: :ok, location: @client }
    end
  end

  def import
    text = params[:text]
  end

  def role_employee 
    people = Client.find params[:id]
    if (people.role.to_i & Client::Role::STUFF) == 0
      new_role = people.role.to_i + (Client::Role::STUFF).to_s(2).to_i
      people.update_attribute(:role, new_role)
      redirect_to company_client_path(@current_company.id, params[:id]), notice: "#{people.last_name} #{people.first_name} получает роль \"Сотрудник\""
    elsif (people.role.to_i & Client::Role::CLIENT) > 0
      redirect_to company_client_path(@current_company.id, params[:id]), notice: "Человек уже является сотрудником"
    else
      redirect_to company_client_path(@current_company.id, params[:id]), notice: "Не удалось изменить роль"
    end
  end

  def role_client
    people = Client.find params[:id]
    if (people.role.to_i & Client::Role::CLIENT) == 0
      new_role = people.role.to_i + (Client::Role::CLIENT).to_s(2).to_i
      people.update_attribute(:role, new_role)
      redirect_to company_client_path(@current_company.id, params[:id]), notice: "#{people.last_name} #{people.first_name} получает роль \"Клиент\""
    elsif (people.role.to_i & Client::Role::CLIENT) > 0
      redirect_to company_client_path(@current_company.id, params[:id]), notice: "Человек уже является клиентом"
    else
      redirect_to company_client_path(@current_company.id, params[:id]), notice: "Не удалось изменить роль"
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_record_client
      # clients_user_company = Client.where company_id: @current_company, user_id: current_user.people_id
      # получаем связи с записями выбранного пользователем человека
      # if @current_record.present?
        records_clients = RecordClient.where client_id: current_user.people_id

        @current_record_client = RecordClient.where("
          record_id IN (?) OR id IN (?)",
          @current_record.select(:id),
          records_clients.select(:id))
      # end
    end

    def set_client
      @client = Client.find_by(company_id: @current_company.id, id: params[:id])
    end

    # Never trust parameters from the scary internet, only allow the white list through.
    def client_params
      res = params.require(:client)
        .permit(:first_name, :last_name, :patronymic, 
                :birthday, :phone_number, :sex, :avatar,
                field_data_attributes: [:id, :field_id, :value])
        .merge(company_id: @current_company.id)

      res[:avatar] = nil if params[:client][:avatar].blank?
      res
    end
    def set_s3_direct_post
      args = {
          key: "images/#{SecureRandom.uuid}/${filename}",
          success_action_status: '201',
          acl: 'public-read'
      }
      @s3_direct_post = S3_BUCKET.presigned_post(args)
    end
end
