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
require_relative '../model/npc'
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
      handle_say_text(room_id: event.room&.id, text: event.data[:text].to_s)
    end

    def handle_say_text(room_id:, text:)
      updates = 0

      updates += advance_objectives(
        objective_type: "say",
        target_type: "npc",
        room_id: room_id,
        metadata: { text: text.to_s }
      )

      updates += advance_objectives(
        objective_type: "say",
        target_type: "room",
        room_id: room_id,
        metadata: { text: text.to_s }
      )

      updates
    end

    def handle_examine(target:, room_id:, target_type: "prop")
      return unless player_character?

      target_id = target.respond_to?(:id) ? target.id.to_s : target.to_s
      metadata = { prop_name: target.respond_to?(:name) ? target.name.to_s : nil }

      if target.respond_to?(:game_object)
        obj = target.game_object
        target_id = obj&.id&.to_s || target_id
        metadata[:object_name] = obj&.name.to_s
        metadata[:object_id] = obj&.id
      elsif target.respond_to?(:item_type) || target.respond_to?(:description)
        metadata[:object_name] = target.respond_to?(:name) ? target.name.to_s : nil
        metadata[:object_id] = target.respond_to?(:id) ? target.id : nil
      end

      advance_objectives(
        objective_type: "examine",
        target_type: target_type,
        target_id: target_id,
        room_id: room_id,
        metadata: metadata
      )
    end

    def handle_visit(room_id:)
      return unless player_character?

      target_id = room_id&.to_s

      advance_objectives(
        objective_type: "visit",
        target_type: "room",
        target_id: target_id,
        room_id: room_id,
        metadata: {}
      )
    end

    def handle_collect(item:, room_id:)
      return unless player_character?

      obj = item.respond_to?(:game_object) ? item.game_object : item
      target_id = obj&.id&.to_s || item&.id&.to_s
      metadata = {
        object_name: obj&.name.to_s,
        object_id: obj&.id
      }

      advance_objectives(
        objective_type: "collect",
        target_type: "object",
        target_id: target_id,
        room_id: room_id,
        metadata: metadata
      )
    end

    def handle_deliver(npc_id:, room_id:, item:)
      return { updates: 0, consume_item: false } unless player_character?

      obj = item.respond_to?(:game_object) ? item.game_object : item
      target_id = npc_id.to_s
      metadata = {
        object_name: obj&.name.to_s,
        object_id: obj&.id
      }

      consume_item = false

      updates = advance_objectives(
        objective_type: "deliver",
        target_type: "npc",
        target_id: target_id,
        room_id: room_id,
        metadata: metadata
      ) do |completed_obj|
        params = parse_parameters(completed_obj.parameters_json)
        consume_item ||= params["consume_item_on_complete"].to_i == 1
      end

      { updates: updates, consume_item: consume_item }
    end

    def say_hint(room_id:, text:)
      return nil unless player_character?
      return nil unless defined?(CharacterQuest) && defined?(QuestObjective)

      active_quests = CharacterQuest.where(character_id: @character.id, state: "active")
      return nil if active_quests.empty?

      active_quests.each do |cq|
        step = current_step_for(cq)
        next if step.nil?

        objectives = QuestObjective.where(
          quest_id: cq.quest_id,
          step_id: step.id,
          objective_type: "say"
        )

        objectives.each do |obj|
          next if obj.target_type.present? && !["npc", "room"].include?(obj.target_type.to_s)
          next if obj.target_room_id.present? && room_id.present? && obj.target_room_id.to_i != room_id.to_i
          next if obj.target_room_id.present? && room_id.nil?

          params = parse_parameters(obj.parameters_json)
          if params["allowed_room_ids"].present?
            allowed = params["allowed_room_ids"].map(&:to_i)
            next if room_id.nil? || !allowed.include?(room_id.to_i)
          end

          if obj.target_type.to_s == "npc" && obj.target_id.present?
            next unless npc_in_room?(obj.target_id, room_id)
          end

          if params["requires_npc_id"].present?
            next unless npc_in_room?(params["requires_npc_id"], room_id)
          end

          hint = params["dialog_hint"].to_s.strip
          next if hint.empty?
          next if say_text_matches?(params, text.to_s)

          if defined?(CharacterQuestObjective)
            cqo = CharacterQuestObjective.find_by(
              character_quest_id: cq.id,
              quest_objective_id: obj.id
            )
            next if cqo && objective_completion_column && objective_completed?(cqo, objective_completion_column)
          end

          return hint
        end
      end

      nil
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

    def npc_in_room?(npc_id, room_id)
      return false if npc_id.nil? || room_id.nil?

      npc = NPC.find_by(id: npc_id.to_i)
      npc.present? && npc.room_id.to_i == room_id.to_i
    end

    def say_text_matches?(params, text)
      normalized = text.to_s.strip.downcase

      min_words = params["min_words"].to_i
      if params["min_words"].present? && min_words > 0
        return false if normalized.split(/\s+/).size < min_words
      end

      exact_phrase = params["exact_phrase"].to_s.strip.downcase
      return false if exact_phrase.present? && normalized != exact_phrase

      expected_text = params["expected_text"].to_s.strip.downcase
      return false if expected_text.present? && normalized != expected_text

      keywords_any = Array(params["keywords_any"]).map(&:to_s).map(&:strip).reject(&:empty?).map(&:downcase)
      if keywords_any.any?
        return false unless keywords_any.any? { |keyword| normalized.include?(keyword) }
      end

      keywords_all = Array(params["keywords_all"]).map(&:to_s).map(&:strip).reject(&:empty?).map(&:downcase)
      if keywords_all.any?
        return false unless keywords_all.all? { |keyword| normalized.include?(keyword) }
      end

      true
    end

    def advance_objectives(objective_type:, target_type:, room_id:, target_id: nil, quest_id: nil, metadata: {}, mark_complete: false)
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
          if obj.target_id.present? && target_id.present? && obj.target_id.to_s != target_id.to_s
            if target_type.to_s == "object" && metadata[:object_name].present?
              expected = obj.target_id.to_s.strip.downcase
              actual = metadata[:object_name].to_s.strip.downcase
              next unless actual.include?(expected)
            else
              next
            end
          end

          if obj.target_id.present? && target_id.nil?
            if objective_type.to_s == "say" && target_type.to_s == "npc"
              next unless npc_in_room?(obj.target_id, room_id)
            else
              next
            end
          end

          next if obj.target_room_id.present? && room_id.present? && obj.target_room_id.to_i != room_id.to_i
          next if obj.target_room_id.present? && room_id.nil?

          params = parse_parameters(obj.parameters_json)
          print params
          if params["allowed_room_ids"].present?
            allowed = params["allowed_room_ids"].map(&:to_i)
            next if room_id.nil? || !allowed.include?(room_id.to_i)
          end

          if params["requires_npc_id"].present?
            next unless npc_in_room?(params["requires_npc_id"], room_id)
          end

          if objective_type.to_s == "say"
            next unless say_text_matches?(params, metadata[:text].to_s)
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

          if params["match_name"].present?
            expected = params["match_name"].to_s.strip.downcase
            actual = metadata[:object_name].to_s.strip.downcase
            actual = metadata[:prop_name].to_s.strip.downcase if actual.empty?
            next if actual.empty? || !actual.include?(expected)
          end

          if params["item_object_id"].present?
            item_id = params["item_object_id"].to_i
            actual_id = metadata[:object_id].to_i
            next if item_id <= 0 || actual_id <= 0 || item_id != actual_id
          end

          if params["requires_previous_steps_complete"].to_i == 1
            next unless previous_steps_complete?(cq, step.step_number.to_i)
          end

          # if objective_type.to_s == "say"
          #   response_text = obj.response_text.to_s.strip
          #   print response_text if response_text.present?
          # end

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

          completed_now = false
          if obj.required_count.to_i <= cqo.current_count.to_i
            cqo.send("#{completion_column}=", completion_value(true)) if completion_column
            cqo.completed_at = Time.now
            completed_now = true
          end

          cqo.save!

          cq.last_progress_at = Time.now
          cq.save!
          print "here 2"

          if completed_now
            notify_npc_saying(obj, room_id)
            yield obj if block_given?
          end
          print "here 3"

          updates += 1
          print "updates: #{updates}"
        end

        advance_step_if_ready(cq, step)
      end

      updates
    end

    def current_step_for(character_quest)
      step_num = character_quest.current_step_number.to_i

      QuestStep.find_by(quest_id: character_quest.quest_id, step_number: step_num) ||
        QuestStep.where(quest_id: character_quest.quest_id).order(:step_number).first
    end

    def advance_step_if_ready(character_quest, step)
      print "STEP: #{step.step_number}"
      completion_column = objective_completion_column
      return if completion_column.nil?

      objectives = QuestObjective.where(quest_id: character_quest.quest_id, step_id: step.id)
      print "objectives: #{objectives.awesome_inspect}"
      return if objectives.empty?

      cqo_rows = CharacterQuestObjective.where(
        character_quest_id: character_quest.id,
        quest_objective_id: objectives.map(&:id)
      ).to_a
      print "cqo_rows: #{cqo_rows.awesome_inspect}"
      return if cqo_rows.empty?

      all_complete = cqo_rows.all? { |row| objective_completed?(row, completion_column) }
      print "step: #{step.awesome_inspect}"

      #return unless all_complete
      print "character_quest: #{character_quest.awesome_inspect}"
      print "character_quest.quest_id: #{character_quest.quest_id}"
      print "step.step_number: #{step.step_number}"

      next_step = QuestStep.where(quest_id: character_quest.quest_id)
                           .where("step_number > ?", step.step_number)
                           .order(:step_number)
                           .first

      print "next_step: #{next_step.awesome_inspect}"
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

      character_quest.state = "completed"
      character_quest.completed_at = Time.now

      if quest.repeatable?
        cooldown_seconds = quest.cooldown_seconds.to_i
        character_quest.cooldown_until = Time.now + cooldown_seconds if cooldown_seconds > 0
      end

      character_quest.save!

      apply_rewards(quest)
    end

    def apply_rewards(quest)
      return if quest.nil? || !defined?(QuestReward)

      QuestReward.where(quest_id: quest.id).order(:reward_order).each do |reward|
        case reward.reward_type.to_s
        when "credits"
          @character.credits = @character.credits.to_i + reward.amount.to_i
          @character.save!
        when "xp"
          @character.experience = @character.experience.to_i + reward.amount.to_i
          @character.save!
        when "flag"
          next if reward.flag_key.to_s.strip.empty?
          flag = CharacterFlag.find_or_initialize_by(
            character_id: @character.id,
            flag_key: reward.flag_key
          )
          flag.flag_value = reward.flag_value.presence || "1"
          flag.set_by_quest_id = quest.id
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

    # language: ruby
    def parse_parameters(parameters_json)
      return {} if parameters_json.blank?
      return parameters_json if parameters_json.is_a?(Hash)

      str = parameters_json.to_s
      begin
        JSON.parse(str)
      rescue JSON::ParserError
        begin
          require 'yaml'
          YAML.safe_load(str) || {}
        rescue StandardError
          {}
        end
      end
    end

    def notify_step_complete(character_quest, step, objectives, next_step)
      return unless @character.respond_to?(:client)

      accomplished = step.description.to_s.strip
      accomplished = "Step #{step.step_number} - #{step.name}." if accomplished.empty?
      step_summary = accomplished

      print "#{$pastel.bright_green('Quest step complete!')} #{$pastel.green(step_summary)}\n"

      next_description = next_step.description.to_s.strip
      next_description = "Step #{next_step.step_number} - #{next_step.name}." if next_description.empty?
      step_label = "Next Step: #{next_step.name}".strip
      print "#{$pastel.bright_cyan(step_label)}"
      print " - #{$pastel.yellow(next_description)}\n"

      if defined?(World::Manager)
        World::Manager.notify_room(@character.name, "#{@character.name} completed a quest step: #{step_summary}", @character.x, @character.y, @character.z)
      end
    end

    def notify_npc_saying(objective, room_id)
      return unless objective.response_text.present?
      return unless objective.target_type.to_s == "npc"
      return if room_id.nil?

      npc = NPC.find_by(id: objective.target_id.to_i)
      return if npc.nil? || npc.room_id.to_i != room_id.to_i

      print objective.response_text
    end




    private

    def print(text)
      return if text.nil?
      return unless @character.respond_to?(:client) && @character.client

      @character.client.puts(Lands.word_wrap(text) + "\r")
    rescue Errno::ECONNRESET, Errno::EPIPE, EOFError, IOError, SystemCallError
      @character.logout_player if @character.respond_to?(:logout_player)
    end

  end
end
