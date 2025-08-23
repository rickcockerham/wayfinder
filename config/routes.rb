Rails.application.routes.draw do

  root "home#index"

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

end
