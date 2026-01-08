class QuestObjective < ActiveRecord::Base
  self.table_name = :quest_objectives

  belongs_to :quest
  belongs_to :quest_step, optional: true

  # Common objective types you’ll likely use:
  # - "kill_creature"
  # - "collect_item"
  # - "visit_room"
  # - "say_to_npc"
  # - "interact_object"
end