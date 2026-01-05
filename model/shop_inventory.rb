class ShopInventory < ActiveRecord::Base
  self.table_name = :shop_inventory
  belongs_to :shop
  belongs_to :game_object, foreign_key: :object_id
end
