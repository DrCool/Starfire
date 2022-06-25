class Creature < ActiveRecord::Base
  belongs_to :room
  has_many :creature_instances
end
