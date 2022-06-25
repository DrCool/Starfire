class Room < ActiveRecord::Base
  has_many :npc, class_name: "NPC"
  has_many :player_characters, -> { where logged_in: true }
  has_many :props
  has_many :creature_instances, -> { where dead: false }
  #has_many :objects
end
