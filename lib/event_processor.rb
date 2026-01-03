module World
  class ShipMover
    def initialize(ships)
    end

    def process_queue
      # Re-query each tick so newly-created ships are included and deleted ships aren't retained.
      Ship.where(is_automated: true).find_each do |ship|
        begin
          ship.reload
          ship.update_status
        rescue => e
          # Don't let one bad ship kill the mover thread
          warn "[ShipMover] ship_id=#{ship.id} error=#{e.class}: #{e.message}"
        end
      end
    end
  end


  class EventProcessor
    EVENT_SPAWN_TIMER = 0

    def initialize
      @q = []
      @creatures = []
    end

    def process_event(event)
      if event.action == ACTION_DIE and event.sender_type == SENDER_TYPE_CREATURE
        creature = Creature.find(event.creature_id)
        spawn_event = {
          type: EVENT_SPAWN_TIMER,
          creature_id: event.creature_id,
          room: event.room,
          room_id: event.room.id,
          spawn_time: creature[:spawn_time].seconds.from_now,
          to_be_deleted: false
        }
        @q << OpenStruct.new(spawn_event)
      end
    end

    def process_queue
      return if @q.empty?

      @q = @q.map! do |item|
        if not item.to_be_deleted
          if Time.now > item.spawn_time and item.type == EVENT_SPAWN_TIMER
            c = Creature.find(item.creature_id)
            creature = CreatureInstance.new
            creature.creature_id = c.id
            creature.room_id = item.room_id
            creature.room = item.room
            creature.hp = c.hp
            creature.creature_name = c.name
            creature.credits = rand(c.credits_min..c.credits_max)
            creature.save

            World::Manager.room_event(Event.new({
              action: ACTION_SPAWN_CREATURE,
              room: creature.room,
              creature: creature,
              message: "#{creature.indef_article.capitalize}#{c.name} appeared.",
              sender_type: SENDER_TYPE_CREATURE
            }))
            item.to_be_deleted = true
          end
        end
        item
      end

      @q.delete_if {|x| x.to_be_deleted == true}
    end
  end
end
