class QuestStep < ActiveRecord::Base
  self.table_name = :quest_steps

  belongs_to :quest

  scope :ordered, -> { order(:step_number) }
end
