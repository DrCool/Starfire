class NPCMovement < ActiveRecord::Base
  belongs_to :npc, class_name: "NPC"
end
