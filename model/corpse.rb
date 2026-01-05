class Corpse < ActiveRecord::Base
  belongs_to :room
  belongs_to :creature_instance
end
