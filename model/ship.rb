require 'tribe'
require_relative '../lib/actable'

class Ship < ActiveRecord::Base
  include Tribe::Actable
  include Lands::Actable

  belongs_to :creature
  belongs_to :room
  after_initialize :after_initialize
  @event_q = []

  def after_initialize
    options = {
      :name => self.ship_name
    }
    begin
      init_actable options
    rescue Tribe::RegistryError
    end
  end

end
