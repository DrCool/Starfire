class CharacterQuest < ActiveRecord::Base
  belongs_to :player_character, foreign_key: :id
  belongs_to :quest
  self.table_name = :character_quests
end
