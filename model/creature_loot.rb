class CreatureLoot < ActiveRecord::Base
  belongs_to :creature
  belongs_to :game_object, foreign_key: :object_id
end
