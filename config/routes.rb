Rails.application.routes.draw do
  namespace :api, defaults: { format: :json } do
    resources :item_blocks, only: %i[index show create destroy]
    resources :locations, only: %i[index show create]
    resources :inventory_items, only: %i[index show]
    put "inventory_items", to: "inventory_items#set_count"
    resources :items, only: %i[index show create update destroy] do
      get :priorities, on: :collection
    end
  end


  root "home#index"
  resource :importance_setting, only: [:show, :update]

  resources :items do
    member do
      get  :materials      # /items/:id/materials
      post :materials_post      # bulk add/update
    end
  end
  get  "shopping",          to: "shopping#index"
  post "shopping/purchase", to: "shopping#purchase", as: :shopping_purchase

  resources :material_requirements
  resources :inventory_items
  resources :item_blocks
  resources :categories
  resources :moods
  resources :locations
  resources :shops
  resources :items

  get  "/login",  to: "sessions#new"
  post "/login",  to: "sessions#create"
  delete "/logout", to: "sessions#destroy"

  get  "/planner", to: "schedule_entries#index", as: :planner
  resources :schedule_entries, only: [:create, :destroy] do
    collection do
      delete :clear # ?on_date=YYYY-MM-DD&day_part=morning
    end
  end

end
