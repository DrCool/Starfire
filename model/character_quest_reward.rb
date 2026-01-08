class CharacterQuestReward < ActiveRecord::Base
  self.table_name = :character_quest_rewards

  belongs_to :character_quest
  belongs_to :quest_reward

  # Optional table if you want to track claimed rewards / anti-duplication
end