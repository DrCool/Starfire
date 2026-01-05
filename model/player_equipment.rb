class PlayerEquipment < ActiveRecord::Base
  self.table_name = :player_equipment
  belongs_to :player_character
  belongs_to :game_object, foreign_key: :object_id
end
