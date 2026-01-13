require_relative 'quest_progression'

module World
  module QuestEvents
    def self.register(action, &block)
      handlers[action] << block
    end

    def self.process(event)
      ensure_defaults!
      handlers[event.action].each { |handler| handler.call(event) }
    end

    def self.handlers
      @handlers ||= Hash.new { |hash, key| hash[key] = [] }
    end

    def self.ensure_defaults!
      return if @defaults_registered

      register(ACTION_DIE) do |event|
        next unless event.sender_type == SENDER_TYPE_CREATURE
        next if event.data&.[](:quest_progressed)

        attacker = event.data[:attacker]
        next unless attacker.is_a?(PlayerCharacter)

        QuestProgression.new(attacker).handle_creature_death(event)
      end

      register(ACTION_SAY) do |event|
        next unless event.sender_type == SENDER_TYPE_PLAYER

        player = event.player
        next unless player.is_a?(PlayerCharacter)

        QuestProgression.new(player).handle_say(event)
      end

      @defaults_registered = true
    end
  end
end
