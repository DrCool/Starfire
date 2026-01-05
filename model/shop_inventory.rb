class ShopInventory < ActiveRecord::Base
  belongs_to :shop
  belongs_to :game_object, foreign_key: :object_id
end
