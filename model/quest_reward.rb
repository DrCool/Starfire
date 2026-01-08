class QuestReward < ActiveRecord::Base
  self.table_name = :quest_rewards

  belongs_to :quest

  # reward_type examples:
  # - "credits"
  # - "xp"
  # - "item" (use object_id + amount)
end