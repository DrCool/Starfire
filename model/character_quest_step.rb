class CharacterQuestStep < ActiveRecord::Base
  self.table_name = :character_quest_steps

  belongs_to :character_quest
  belongs_to :quest_step

  # Optional table if you chose to track:
  # - per-step state
  # - timestamps
end