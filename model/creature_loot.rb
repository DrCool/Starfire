class CreatureLoot < ActiveRecord::Base
  self.table_name = :creature_loot
  belongs_to :creature
  belongs_to :game_object, foreign_key: :object_id
end
