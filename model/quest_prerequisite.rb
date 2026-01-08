class QuestPrerequisite < ActiveRecord::Base
  self.table_name = :quest_prerequisites

  belongs_to :quest

  # prereq_type examples:
  # - "level"
  # - "quest_completed"
  # - "flag"
end