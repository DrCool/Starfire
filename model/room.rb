class Room < ActiveRecord::Base
  belongs_to :zone
  has_many :npc, class_name: "NPC"
  has_many :player_characters, -> { where logged_in: true }
  has_many :props
  has_many :creature_instances, -> { where dead: false }
  has_many :inventory_items, -> { where owner_type: "Room" }, foreign_key: :owner_id
  has_many :corpses
end
