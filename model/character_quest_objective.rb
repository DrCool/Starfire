class CharacterQuestObjective < ActiveRecord::Base
  self.table_name = :character_quest_objectives

  belongs_to :character_quest
  belongs_to :quest_objective

  # Track progress per objective:
  # - current_count
  # - is_complete
end