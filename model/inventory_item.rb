class InventoryItem < ActiveRecord::Base
  belongs_to :game_object, foreign_key: :object_id
end
