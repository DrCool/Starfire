class ShipMovement < ActiveRecord::Base
  self.table_name = :ship_movements
  belongs_to :ship
end
