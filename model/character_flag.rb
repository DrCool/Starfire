class CharacterFlag < ActiveRecord::Base
  self.table_name = :character_flags

  belongs_to :player_character

  # flag_key examples:
  # - "quest.kfo.skitter_sweep.completed"
  # flag_value typically:
  # - "1" (or other string values)
end