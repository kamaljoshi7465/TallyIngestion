Rails.application.routes.draw do
  get "/health", to: "health#index"
  
  resources :imports, only: [:create, :show] do
    member do
      get :vouchers
    end
  end
end
