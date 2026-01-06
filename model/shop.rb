class Shop < ActiveRecord::Base
  has_many :shop_inventory
  belongs_to :room
end
