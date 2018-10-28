Rails.application.routes.draw do
  namespace :companies do
    get 'windows/show'
  end

  root 'home#index'
  get 'iairgmqqimuuoeexaspwkjykrtaocalendar' => 'home#add_subscriptions_automatically'
  get 'upewuadesutgqavgimmwvdwfizyfgwperiod' => 'home#automatically_by_period'

  devise_for :users, path: 'auth', controllers: {confirmations: 'confirmations'}
  get 'auth' => 'home#auth'
  get 'search_result' => 'home#search_result'
  get 'add_field' => 'home#add_field'
  get 'account' => 'home#account'
  get 'persons/profile'
  get 'persons/new_profile'
  post 'persons/role_person/:role_person' => 'persons#role_person', as: 'role_person'
  get 'company' => 'companies#company'

  get 'get_clients' => 'home#get_clients'
  get 'get_data' => 'home#get_data'

  resources :companies do
    get 'add_field' => 'companies#add_field', module: :companies

    resources :affiliates, module: :companies
    resources :records, module: :companies do
      member do
        get 'end_recording'
      end
    end
    post 'clients/:id/archive/:archive_status' => 'companies/clients#archive', as: 'clients_archive'
    resources :clients, module: :companies do
      member do
        # patch 'import'
        get 'role_employee'
        get 'role_client'
        post 'add_field'
      end
    end
    resources :workers, module: :companies do
      member do
        get 'role_employee'
        get 'role_client'
      end
    end
    post 'clients/import' => 'companies/clients#import'
    resources :services, module: :companies
    resources :subscriptions, module: :companies do
      member do
        patch 'cancel'
      end
    end
    resources :fin_operations, module: :companies do
      member do
        get 'doc_pko'
      end
    end
    resources :histories, module: :companies
    resources :info_blocks, module: :companies
    resources :field_templates, module: :companies
    resources :field_data, module: :companies
    resources :works, module: :companies
    resources :salaries, module: :companies
  end
  # two primary keys
  delete 'records_services' => 'records_services#destroy'
  patch 'records_services' => 'records_services#update'
  resources :records_services
  resources :records_clients
  resources :windows, only: :show
  resources :discounts
  resources :works_salaries
end
