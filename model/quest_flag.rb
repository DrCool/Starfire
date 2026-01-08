class QuestFlag < ActiveRecord::Base
  self.table_name = :quest_flags

  belongs_to :quest
  belongs_to :quest_step, optional: true

  # This is the “what flags get set when X happens” table
  # (e.g., when step 2 completes, set quest.kfo.skitter_sweep.completed=1)
end