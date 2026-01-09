require 'json'
require_relative '../model/character_flag'
require_relative '../model/character_quest'
require_relative '../model/character_quest_objective'
require_relative '../model/player_character'
require_relative '../model/quest'
require_relative '../model/quest_objective'
require_relative '../model/quest_reward'
require_relative '../model/quest_step'
require_relative '../model/room'
require_relative '../model/event'

module World
  class QuestProgression
    def initialize(character)
      @character = character
    end

    def handle_creature_death(event)
      return unless player_character?

      creature_id = event.creature_id.to_i
      room_id = event.room&.id

      advance_objectives(
        objective_type: "kill",
        target_type: "creature",
        target_id: creature_id.to_s,
        room_id: room_id
      )
    end

    def handle_say(event)
      return unless player_character?

      advance_objectives(
        objective_type: "say",
        target_type: "npc",
        room_id: event.room&.id,
        metadata: { text: event.data[:text].to_s }
      )
    end

    def handle_examine(target:, room_id:)
      return unless player_character?

      target_id = target.respond_to?(:id) ? target.id.to_s : target.to_s
      metadata = { prop_name: target.respond_to?(:name) ? target.name.to_s : nil }

      advance_objectives(
        objective_type: "examine",
        target_type: "prop",
        target_id: target_id,
        room_id: room_id,
        metadata: metadata
      )
    end

    def handle_turn_in(quest_id:, room_id:)
      return 0 unless player_character?

      advance_objectives(
        objective_type: "turnin",
        target_type: "room",
        room_id: room_id,
        quest_id: quest_id,
        mark_complete: true
      )
    end

    private

    def player_character?
      @character.is_a?(PlayerCharacter)
    end

    def advance_objectives(objective_type:, target_type:, room_id:, target_id: nil, quest_id: nil, metadata: {}, mark_complete: false)
      return 0 unless defined?(CharacterQuest) && defined?(QuestObjective)

      active_quests = CharacterQuest.where(character_id: @character.id, state: "active")
      active_quests = active_quests.where(quest_id: quest_id) if quest_id.present?
      return 0 if active_quests.empty?

      updates = 0

      active_quests.each do |cq|
        step = current_step_for(cq)
        next if step.nil?

        objectives = QuestObjective.where(
          quest_id: cq.quest_id,
          step_id: step.id,
          objective_type: objective_type
        )

        objectives.each do |obj|
          next if obj.target_type.present? && obj.target_type.to_s != target_type.to_s
          next if obj.target_id.present? && target_id.present? && obj.target_id.to_s != target_id.to_s
          next if obj.target_id.present? && target_id.nil?

          next if obj.target_room_id.present? && room_id.present? && obj.target_room_id.to_i != room_id.to_i
          next if obj.target_room_id.present? && room_id.nil?

          params = parse_parameters(obj.parameters_json)
          if params["allowed_room_ids"].present?
            allowed = params["allowed_room_ids"].map(&:to_i)
            next if room_id.nil? || !allowed.include?(room_id.to_i)
          end

          if params["expected_text"].present?
            expected = params["expected_text"].to_s.strip.downcase
            heard = metadata[:text].to_s.strip.downcase
            next unless expected == heard
          end

          if params["prop_name"].present?
            expected = params["prop_name"].to_s.strip.downcase
            actual = metadata[:prop_name].to_s.strip.downcase
            next if actual.empty? || !actual.include?(expected)
          end

          if params["requires_previous_steps_complete"].to_i == 1
            next unless previous_steps_complete?(cq, step.step_number.to_i)
          end

          cqo = CharacterQuestObjective.find_or_create_by!(
            character_quest_id: cq.id,
            quest_objective_id: obj.id
          )

          completion_column = objective_completion_column
          completed = completion_column && objective_completed?(cqo, completion_column)
          next if completed

          if mark_complete
            cqo.current_count = obj.required_count.to_i
          else
            current = cqo.current_count.to_i
            cqo.current_count = current + 1
          end

          if obj.required_count.to_i <= cqo.current_count.to_i
            cqo.send("#{completion_column}=", completion_value(true)) if completion_column
            cqo.completed_at = Time.now
          end

          cqo.save!

          cq.last_progress_at = Time.now if cq.respond_to?(:last_progress_at=)
          cq.save!
          updates += 1
        end

        advance_step_if_ready(cq, step)
      end

      updates
    end

    def current_step_for(character_quest)
      return nil unless defined?(QuestStep)

      step_no = 1
      if character_quest.respond_to?(:current_step_number) && character_quest.current_step_number.present?
        step_no = character_quest.current_step_number.to_i
      end

      QuestStep.find_by(quest_id: character_quest.quest_id, step_number: step_no) ||
        QuestStep.where(quest_id: character_quest.quest_id).order(:step_number).first
    end

    def advance_step_if_ready(character_quest, step)
      completion_column = objective_completion_column
      return if completion_column.nil?

      objectives = QuestObjective.where(quest_id: character_quest.quest_id, step_id: step.id)
      return if objectives.empty?

      cqo_rows = CharacterQuestObjective.where(
        character_quest_id: character_quest.id,
        quest_objective_id: objectives.map(&:id)
      ).to_a
      return if cqo_rows.empty?

      all_complete = cqo_rows.all? { |row| objective_completed?(row, completion_column) }
      return unless all_complete

      next_step = QuestStep.where(quest_id: character_quest.quest_id)
                           .where("step_number > ?", step.step_number)
                           .order(:step_number)
                           .first

      if next_step
        notify_step_complete(character_quest, step, objectives, next_step)
        character_quest.current_step_number = next_step.step_number if character_quest.respond_to?(:current_step_number=)
        character_quest.save!
      else
        complete_quest(character_quest)
      end
    end

    def complete_quest(character_quest)
      quest = Quest.find_by(id: character_quest.quest_id)

      character_quest.state = "completed" if character_quest.respond_to?(:state=)
      character_quest.completed_at = Time.now if character_quest.respond_to?(:completed_at=)

      if quest&.respond_to?(:repeatable?) && quest.repeatable? &&
         quest.respond_to?(:cooldown_seconds) && character_quest.respond_to?(:cooldown_until=)
        cooldown_seconds = quest.cooldown_seconds.to_i
        character_quest.cooldown_until = Time.now + cooldown_seconds if cooldown_seconds > 0
      end

      character_quest.save!

      apply_rewards(quest)
    end

    def apply_rewards(quest)
      return if quest.nil? || !defined?(QuestReward)

      QuestReward.where(quest_id: quest.id).order(:order).each do |reward|
        case reward.reward_type.to_s
        when "credits"
          next unless @character.respond_to?(:credits=)
          @character.credits = @character.credits.to_i + reward.amount.to_i
          @character.save!
        when "xp"
          next unless @character.respond_to?(:experience=)
          @character.experience = @character.experience.to_i + reward.amount.to_i
          @character.save!
        when "flag"
          next if reward.flag_key.to_s.strip.empty?
          flag = CharacterFlag.find_or_initialize_by(
            character_id: @character.id,
            flag_key: reward.flag_key
          )
          flag.flag_value = reward.flag_value.presence || "1"
          flag.set_by_quest_id = quest.id if flag.respond_to?(:set_by_quest_id=)
          flag.save!
        end
      end
    end

    def previous_steps_complete?(character_quest, step_number)
      return true if step_number <= 1

      completion_column = objective_completion_column
      return true if completion_column.nil?

      prior_steps = QuestStep.where(quest_id: character_quest.quest_id)
                             .where("step_number < ?", step_number)
      return true if prior_steps.empty?

      prior_objectives = QuestObjective.where(quest_id: character_quest.quest_id, step_id: prior_steps.map(&:id))
      return true if prior_objectives.empty?

      rows = CharacterQuestObjective.where(
        character_quest_id: character_quest.id,
        quest_objective_id: prior_objectives.map(&:id)
      ).to_a
      return false if rows.empty?

      rows.all? { |row| objective_completed?(row, completion_column) }
    end

    def objective_completion_column
      return "is_completed" if CharacterQuestObjective.column_names.include?("is_completed")
      return "is_complete" if CharacterQuestObjective.column_names.include?("is_complete")
      nil
    end

    def objective_completed?(row, completion_column)
      value = row.send(completion_column)
      return true if value == true
      return false if value == false || value.nil?

      value.to_i == 1
    end

    def completion_value(flag)
      return true if CharacterQuestObjective.columns_hash['is_completed']&.type == :boolean

      flag ? 1 : 0
    end

    def parse_parameters(parameters_json)
      return {} if parameters_json.blank?

      JSON.parse(parameters_json.to_s)
    rescue JSON::ParserError
      {}
    end

    def notify_step_complete(character_quest, step, objectives, next_step)
      return unless @character.respond_to?(:client)

      accomplished = step.description.to_s.strip
      accomplished = "Step #{step.step_number} - #{step.name}." if accomplished.empty?
      step_summary = accomplished

      print "#{$pastel.bright_green('Quest step complete!')} #{$pastel.green(step_summary)}"

      next_description = next_step.description.to_s.strip
      next_description = "Step #{next_step.step_number} - #{next_step.name}." if next_description.empty?
      step_label = "Next Step #{next_step.step_number}: #{next_step.name}".strip
      print "#{$pastel.bright_cyan(step_label)}"
      print " - #{$pastel.yellow(next_description)}"

      notify_room(@player, "#{@character.name} completed a quest step: #{step_summary}", @character.x, @character.y, @character.z)
    end

  end
end
