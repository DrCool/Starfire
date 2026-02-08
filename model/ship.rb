require 'tribe'
require_relative '../lib/actable'
require_relative 'ship_movement'

class Ship < ActiveRecord::Base
  validates :ship_name, presence: true
  validates :travel_duration, presence: true, numericality: { greater_than: 0 }
  validates :dock_duration, presence: true, numericality: { greater_than: 0 }
  validate :must_have_at_least_two_stops

  include Tribe::Actable
  include Lands::Actable

  self.table_name = :ships

  # Ship interior (players are here when boarded)
  belongs_to :home_room, class_name: 'Room', foreign_key: 'home_room_id', optional: true

  # Dock/terminal room where the ship is currently docked (nil while in transit)
  belongs_to :dock_room, class_name: 'Room', foreign_key: 'dock_room_id', optional: true

  has_many :ship_movements, -> { order(:order) }, class_name: 'ShipMovement', foreign_key: 'ship_id'

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

  def start_location
    stops = route_stops
    return nil if stops.empty?
    stops.first[:dock_room_id]
  end

  def end_location
    stops = route_stops
    return nil if stops.length < 2
    stops[1][:dock_room_id]
  end

  # Tick method called by ShipMover.
  # Route definition: ship_movements (ordered dock/terminal rooms)
  # Runtime state: ships.state/current_stop_order/next_stop_order/next_at/departed_at + ships.dock_room_id
  # Ship interior: ships.home_room_id (players remain here during transit)
  def update_status
    stops = route_stops
    return if stops.length < 2

    now_i = Time.now.to_i

    # Initialize state
    self.state = 'docked' if self.state.to_s.strip.empty?

    # Seed dock_room_id when docked (if missing)
    if self.state == 'docked' && (dock_room_id.nil? || dock_room_id.to_i == 0)
      self.dock_room_id = stops.first[:dock_room_id]
    end

    # Determine current stop (based on dock_room_id when docked; else use current_stop_order)
    current_stop = nil
    if self.state == 'docked'
      current_stop = stop_for_dock_room_id(dock_room_id, stops)
    end
    current_stop ||= stop_for_order(current_stop_order.to_i, stops)
    current_stop ||= stops.first

    # Seed current/next orders if missing/invalid
    valid_orders = stops.map { |s| s[:order].to_i }
    if current_stop_order.to_i == 0 || !valid_orders.include?(current_stop_order.to_i)
      self.current_stop_order = current_stop[:order]
    end

    if next_stop_order.to_i == 0 || !valid_orders.include?(next_stop_order.to_i)
      self.next_stop_order = stop_after_order(current_stop_order.to_i, stops)[:order]
    end

    # Resolve stop records from orders
    current_stop = stop_for_order(current_stop_order.to_i, stops) || current_stop
    next_stop    = stop_for_order(next_stop_order.to_i, stops) || stop_after_order(current_stop[:order], stops)

    dock_seconds   = (current_stop[:dock_duration] || dock_duration).to_i
    travel_seconds = travel_duration.to_i

    # Seed next_at if missing
    if next_at.to_i == 0
      self.next_at = now_i + (self.state == 'in_transit' ? travel_seconds : dock_seconds)
    end

    case self.state
    when 'docked'
      # Ensure dock_room_id matches current stop
      if dock_room_id.to_i != current_stop[:dock_room_id].to_i
        self.dock_room_id = current_stop[:dock_room_id]
      end

      # When ship is about to leave in 9 seconds, announce to dock + ship interior
      if next_at.to_i - now_i == 9
        emit_room_literal(current_stop[:dock_room_id], $pastel.bright_red(ship_name) + " is about to depart for #{stop_label(next_stop)}.")
        emit_ship_literal($pastel.bright_red(ship_name) + " is about to depart for #{stop_label(next_stop)}.")
      end

      if now_i >= next_at.to_i
        # Depart
        self.state = 'in_transit'
        self.departed_at = now_i
        self.next_at = now_i + travel_seconds

        # While traveling, no dock room
        depart_from = current_stop
        self.dock_room_id = nil

        # Announce to dock + ship interior
        emit_room_literal(depart_from[:dock_room_id], $pastel.bright_red(ship_name) + " departs for #{stop_label(next_stop)}.")
        emit_ship_literal($pastel.bright_red(ship_name) + " undocks and begins its journey to #{stop_label(next_stop)}.")

        # Announce to any rooms that exist up to 1 space away from the dock room
        begin
          dock_room = Room.find_by(id: depart_from[:dock_room_id])
          if dock_room.present?
            adjacent_room_ids = World::Manager.adjacent_room_ids(dock_room.id, 1, :outside)
            adjacent_room_ids.each do |arid|
              emit_room_literal(arid, "You hear the rumble of a ship departing nearby.")
            end

            adjacent_room_ids = World::Manager.adjacent_room_ids(dock_room.id, 1, :inside)
            adjacent_room_ids.each do |arid|
              # If player is in a ship, ignore it
              room = Room.find_by(id: arid)
              next if room.present? && room.room_type_id == 4
              emit_room_literal(arid, "You hear a loud rumble in the distance.")
            end
          end
        rescue => e
          warn "[Ship] ship_id=#{id} failed to announce departure to adjacent rooms: #{e.class}: #{e.message}"
        end
      end

    when 'in_transit'
      if now_i >= next_at.to_i
        # Arrive
        from_stop = current_stop
        dest_stop = next_stop

        self.state = 'docked'
        self.dock_room_id = dest_stop[:dock_room_id]
        self.current_stop_order = dest_stop[:order]
        self.next_stop_order = stop_after_order(dest_stop[:order], stops)[:order]

        dock_seconds = (dest_stop[:dock_duration] || dock_duration).to_i
        self.next_at = now_i + dock_seconds
        self.departed_at = nil

        # Announce to destination dock + ship interior
        emit_room_literal(dest_stop[:dock_room_id], $pastel.bright_red(ship_name) + " arrives from #{stop_label(from_stop)}.")
        emit_room_literal(dest_stop[:dock_room_id], $pastel.bright_red(ship_name) + " is docked for #{dock_seconds} seconds. Type 'board' to enter it.")
        emit_ship_literal($pastel.bright_red(ship_name) + " docks at #{stop_label(dest_stop)}.")

        # Now announce to any rooms that exist up to 1 space away from the dock room
        begin
          dock_room = Room.find_by(id: dest_stop[:dock_room_id])
          if dock_room.present?
            adjacent_room_ids = World::Manager.adjacent_room_ids(dock_room.id, 1, :outside)
            adjacent_room_ids.each do |arid|
              emit_room_literal(arid, "You hear the rumble of a ship landing nearby.")
            end

            adjacent_room_ids = World::Manager.adjacent_room_ids(dock_room.id, 1, :inside)
            adjacent_room_ids.each do |arid|
              # If player is in a ship, ignore it
              room = Room.find_by(id: arid)
              next if room.present? && room.room_type_id == 4
              emit_room_literal(arid, "You hear a loud rumble in the distance.")
            end
          end
        rescue => e
          warn "[Ship] ship_id=#{id} failed to announce arrival to adjacent rooms: #{e.class}: #{e.message}"
        end
      else
        # Still in transit
        # Calculate progress percentage as an integer (0..100)
        departed = departed_at.to_i
        total_travel = next_at.to_i - departed
        elapsed = now_i - departed

        if total_travel <= 0
          progress_int = 0
        else
          progress_int = ((elapsed.to_f / total_travel.to_f) * 100).clamp(0, 100).round.to_i
        end

        # Every 25% progress, emit a message to the ship interior
        if (progress_int % 25).zero?
          if progress_int == 50
            emit_ship_literal($pastel.bright_red(ship_name) + " is halfway to #{stop_label(next_stop)}.")
          else
            emit_ship_literal($pastel.bright_red(ship_name) + " is #{progress_int}% of the way to #{stop_label(next_stop)}.")
          end
        end
      end

    else
      # Unknown state: reset safely
      self.state = 'docked'
      self.dock_room_id ||= current_stop[:dock_room_id]
      self.next_at = now_i + dock_seconds
      self.departed_at = nil
    end

    save!(validate: false)
  end

  def docked_at_room?(room_or_id)
    rid = room_or_id.is_a?(Room) ? room_or_id.id : room_or_id
    return false if rid.nil?

    state == 'docked' && dock_room_id.to_i == rid.to_i
  end

  def route_stops
    rows = ship_movements.to_a
    if rows.length >= 2
      # Build a lightweight struct/hash so we don't hard-couple to associations.
      return rows.map do |sm|
        {
          order: sm.order.to_i,
          dock_room_id: sm.room_id.to_i,
          stop_name: (sm.respond_to?(:stop_name) ? sm.stop_name : nil),
          dock_duration: (sm.respond_to?(:dock_duration) ? sm.dock_duration : nil)
        }
      end.sort_by { |h| h[:order] }
    end

    return []
  end

  def stop_for_order(order, stops)
    stops.find { |s| s[:order].to_i == order.to_i }
  end

  def stop_for_dock_room_id(rid, stops)
    return nil if rid.nil?
    stops.find { |s| s[:dock_room_id].to_i == rid.to_i }
  end

  def stop_after_order(order, stops)
    sorted = stops.sort_by { |s| s[:order].to_i }
    idx = sorted.index { |s| s[:order].to_i == order.to_i }
    return sorted.first if idx.nil?
    sorted[(idx + 1) % sorted.length]
  end

  def stop_label(stop)
    rid = stop[:dock_room_id]
    room = Room.find_by(id: rid)

    name = stop[:stop_name].to_s.strip
    name = room&.name.to_s.strip if name.empty?
    name = "room ##{rid}" if name.empty?
    name
  end

  def emit_ship_literal(message)
    return if home_room_id.nil? || home_room_id.to_i == 0
    emit_room_literal(home_room_id, message)
  end

  # Broadcast a literal message to all players in a room.
  def emit_room_literal(room_id, message)
    return if room_id.nil?
    room = Room.find_by(id: room_id)
    return if room.nil?

    World::Manager.room_event(Event.new({
      action: ACTION_LITERAL,
      room: room,
      message: message,
      data: { ship_id: id },
      sender_type: SENDER_TYPE_ROOM
    }))
  end

  def must_have_at_least_two_stops
    stops = route_stops
    if stops.length < 2
      errors.add(:base, "Ship must have at least two ship_movements stops")
    end
  end
end
