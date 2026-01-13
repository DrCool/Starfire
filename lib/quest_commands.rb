require 'json'
require_relative '../model/inventory_item'
require_relative '../model/game_object'
require_relative 'lands'

# List quests at the current board
def list_quests
  unless @room.room_type_id.to_i == 5
    print "There is no quest board here."
    return
  end

  level = @player.level.to_i

  quests = Quest
             .where(is_active: 1, start_room_id: @room.id)
             .where("min_level IS NULL OR min_level <= ?", level)
             .where("max_level IS NULL OR max_level >= ?", level)
             .order(Arel.sql("COALESCE(min_level, 0) ASC"))
             .order(:id)
             .to_a

  ap quests

  # Apply prerequisites if the table exists.
  if quests_table_exists?("quest_prerequisites")
    quests = quests.select { |q| prerequisites_pass?(q.id) }
  end

  draw_box "", 21, 3
  num_prev_lines = 1
  width = 1
  print_hold "\e[#{num_prev_lines}A"

  print ""
  print "\e[#{width}C" + $pastel.on_red($pastel.bright_white($pastel.bold("                         ")))
  print "\e[#{width}C" + $pastel.on_red($pastel.bright_white($pastel.bold("       Quest Board       ")))
  print "\e[#{width}C" + $pastel.on_red($pastel.bright_white($pastel.bold("                         ")))
  print ""

  if quests.empty?
    print "No quests are posted here."
    return
  end

  now = Time.now

  quests.each do |q|
    quest_id = q.id.to_i
    name = (q.name.presence || q.quest_key.to_s)
    summary = q.summary.to_s
    repeatable = q.repeatable?

    cq = nil
    if quests_table_exists?("character_quests")
      cq = fetch_latest_character_quest(@player.id, quest_id)
    end

    status = "AVAILABLE"
    cooldown_note = nil

    if cq.present?
      state = cq.state.to_s
      cooldown_until = cq.cooldown_until

      cooldown_time = nil
      if cooldown_until.present?
        cooldown_time = cooldown_until.is_a?(Time) ? cooldown_until : Time.parse(cooldown_until.to_s) rescue nil
      end

      if state == "active"
        status = "ACTIVE"
      elsif state == "completed" && !repeatable
        status = "COMPLETED"
      elsif repeatable
        if cooldown_time && cooldown_time > now
          status = "COOLDOWN"
          secs = (cooldown_time - now).to_i
          cooldown_note = "(#{secs}s)"
        else
          status = "AVAILABLE"
        end
      elsif state == "abandoned"
        if cooldown_time && cooldown_time > now
          status = "COOLDOWN"
          secs = (cooldown_time - now).to_i
          cooldown_note = "(#{secs}s)"
        else
          status = "AVAILABLE"
        end
      end
    end

    header = "#{quest_id}) #{name} [#{status}]"
    header += " #{cooldown_note}" if cooldown_note.present?
    print header

    print "   #{summary}" if summary.present?

    rewards = fetch_quest_rewards_summary(quest_id)
    print "   Reward: #{rewards}" if rewards.present?

    print "   Type: accept #{quest_id}"
  end
end

def show_quest_details(text)
  unless @room.room_type_id.to_i == 5
    print "There is no quest board here."
    return
  end

  token = text.to_s.strip.split(" ").first
  unless token.present? && token =~ /^\d+$/
    print "Usage: quests <quest_id>"
    return
  end

  quest_id = token.to_i

  q = Quest.find_by(id: quest_id, is_active: 1, start_room_id: @room.id)
  if q.nil?
    print "That quest is not posted here."
    return
  end

  print ""
  print "#{q.id}) #{q.name.presence || q.quest_key}"

  if q.summary.present?
    print q.summary.to_s
  end

  min_lvl = q.respond_to?(:min_level) ? q.min_level : nil
  max_lvl = q.respond_to?(:max_level) ? q.max_level : nil

  if min_lvl.present? || max_lvl.present?
    req = []
    req << "min #{min_lvl}" if min_lvl.present?
    req << "max #{max_lvl}" if max_lvl.present?
    print "Level: #{req.join(", ") }"
  end

  repeatable = q.repeatable?
  cooldown_seconds = q.respond_to?(:cooldown_seconds) ? q.cooldown_seconds.to_i : 0

  if repeatable
    if cooldown_seconds > 0
      print "Repeatable: yes (cooldown #{cooldown_seconds}s)"
    else
      print "Repeatable: yes"
    end
  else
    print "Repeatable: no"
  end

  rewards = fetch_quest_rewards_summary(q.id)
  print "Reward: #{rewards}" if rewards.present?

  if quests_table_exists?("quest_steps")
    steps = ActiveRecord::Base.connection.exec_query(
      "SELECT step_number, name, description FROM quest_steps WHERE quest_id = #{ActiveRecord::Base.connection.quote(q.id)} ORDER BY step_number ASC"
    ).to_a

    if steps.any?
      print ""
      print "Steps:"
      steps.each do |s|
        step_no = s["step_number"].to_i
        step_name = s["name"].to_s
        step_desc = s["description"].to_s
        print "Step #{step_no}: #{step_name}".strip
        print "   #{step_desc}" if step_desc.present?
      end
    end
  end

  print ""
  print "Type: accept #{q.id}"
  print "Once complete, return here and type: complete #{q.id}"
end

def accept_quest(text)
  unless @room.room_type_id.to_i == 5
    print "You need to be at a job board to accept quests."
    return
  end

  token = text.to_s.strip.split(" ").first
  unless token.present? && token =~ /^\d+$/
    print "Usage: accept <quest_id>"
    return
  end

  quest_id = token.to_i

  q = Quest.find_by(id: quest_id, is_active: 1, start_room_id: @room.id)
  if q.nil?
    print "That quest is not posted here."
    return
  end

  level = @player.level.to_i
  min_lvl = q.respond_to?(:min_level) ? q.min_level : nil
  max_lvl = q.respond_to?(:max_level) ? q.max_level : nil

  if min_lvl.present? && level < min_lvl.to_i
    print "You are not experienced enough for that quest."
    return
  end

  if max_lvl.present? && level > max_lvl.to_i
    print "That quest is meant for less experienced players."
    return
  end

  if quests_table_exists?("quest_prerequisites")
    unless prerequisites_pass?(q.id)
      print "You do not meet the prerequisites for that quest."
      return
    end
  end

  repeatable = q.repeatable?
  cq = fetch_latest_character_quest(@player.id, q.id) if quests_table_exists?("character_quests")

  if cq.present?
    state = cq.state.to_s
    if state == "active"
      print "You have already accepted that quest."
      return
    end

    if state == "completed" && !repeatable
      print "You have already completed that quest."
      return
    end

    if repeatable
      secs = seconds_until(cq.cooldown_until)
      if secs > 0
        print "That quest is not available yet. Check back in #{secs}s."
        return
      end
    end
  end

  fk = character_quest_fk_column

  attrs = {
    fk => @player.id,
    quest_id: q.id,
    state: "active"
  }

  attrs[:current_step_number] = 1 if CharacterQuest.column_names.include?("current_step_number")
  attrs[:started_at] = Time.now if CharacterQuest.column_names.include?("started_at")

  new_cq = CharacterQuest.create!(attrs)

  QuestObjective.where(quest_id: q.id).find_each do |obj|
    oattrs = {
      character_quest_id: new_cq.id,
      quest_objective_id: obj.id
    }
    oattrs[:current_count] = 0 if CharacterQuestObjective.column_names.include?("current_count")
    oattrs[:is_completed] = 0 if CharacterQuestObjective.column_names.include?("is_completed")
    oattrs[:is_complete] = 0 if CharacterQuestObjective.column_names.include?("is_complete")
    CharacterQuestObjective.create!(oattrs)
  end

  print "You accept: #{q.name.presence || q.quest_key}"
  print "Type 'journal' to track your active quests."
rescue => e
  print "Could not accept that quest."
  print "Error: #{e.message}"
end

def complete_quest(text)
  token = text.to_s.strip.split(" ").first
  unless token.present? && token =~ /^\d+$/
    print "Usage: complete <quest_id>"
    return
  end

  quest_id = token.to_i

  cq = active_character_quests.find { |row| row.quest_id.to_i == quest_id }
  if cq.nil?
    print "You do not have that quest active."
    return
  end

  q = Quest.find_by(id: quest_id)
  quest_name = q&.name.presence || q&.quest_key.to_s || "Quest #{quest_id}"

  step = current_step_for(cq)
  if step.nil?
    print "That quest cannot be turned in right now."
    return
  end

  objectives = QuestObjective.where(
    quest_id: quest_id,
    step_id: step.id,
    objective_type: "turnin"
  ).to_a

  if objectives.empty?
    print "That quest cannot be turned in right now."
    return
  end

  turnin = objectives.any? do |obj|
    target_room = obj.target_room_id.to_i if obj.respond_to?(:target_room_id)
    next true if target_room.nil? || target_room == 0
    target_room == @room.id
  end

  unless turnin
    print "You need to be at the turn-in location to complete that quest."
    return
  end

  progress = World::QuestProgression.new(@player)
  updates = progress.handle_turn_in(quest_id: quest_id, room_id: @room.id)

  if updates <= 0
    print "You are not ready to complete that quest."
    return
  end

  cq.reload

  if cq.state.to_s == "completed"
    print "\n"
    print $pastel.on_green($pastel.white(" Quest completed: ")) + $pastel.green("#{quest_name}")
    rewards = fetch_quest_rewards_summary(quest_id)
    print "Reward: #{rewards}" if rewards.present?
  else
    print "Quest updated: #{quest_name}"
  end
rescue => e
  print "Could not complete that quest."
  print "Error: #{e.message}"
end

def check_for_quest_objective(details = {}, target_type = nil, target_id = nil)
  if !details.is_a?(Hash)
    details = {
      objective_type: details,
      target_type: target_type,
      target_id: target_id
    }
  end

  objective_type = details[:objective_type].to_s
  target_type = details[:target_type].to_s
  command_text = details[:command_text].to_s
  action = objective_type.to_s
  prop = details[:prop] || resolve_prop_in_room(command_text) if target_type == "prop"
  obj = details[:object] || details[:item] if target_type == "object"

  return if action.strip.empty?

  case action.to_s

  when "examine"
    if target_type == "object"
      return if obj.nil?

      progress = World::QuestProgression.new(@player)
      updates = progress.handle_examine(target: obj, room_id: @room&.id, target_type: "object")
      print $pastel.green("Journal updated.") if updates.to_i > 0
    else
      return if prop.nil?

      progress = World::QuestProgression.new(@player)
      updates = progress.handle_examine(target: prop, room_id: @room&.id, target_type: "prop")
      print $pastel.green("Journal updated.") if updates.to_i > 0
    end

  when "visit"
    if target_type == "room"
      ensure_room_quest_objects(@room&.id)
      progress = World::QuestProgression.new(@player)
      updates = progress.handle_visit(room_id: @room&.id)
      print $pastel.green("Journal updated.") if updates.to_i > 0
    end

  when "collect"
    return if obj.nil?

    progress = World::QuestProgression.new(@player)
    updates = progress.handle_collect(item: obj, room_id: @room&.id)
    print $pastel.green("Journal updated.") if updates.to_i > 0

  when "deliver"
    return if details[:npc].nil? || obj.nil?

    progress = World::QuestProgression.new(@player)
    result = progress.handle_deliver(
      npc_id: details[:npc].id,
      room_id: @room&.id,
      item: obj
    )
    print $pastel.green("Journal updated.") if result[:updates].to_i > 0

  when "say"
    progress = World::QuestProgression.new(@player)
    updates = progress.handle_say_text(room_id: @room.id, text: command_text)
    print $pastel.green("Journal updated.") if updates.to_i > 0
  end
end

def ensure_room_quest_objects(room_id)
  return if room_id.nil?
  return unless defined?(CharacterQuest) && defined?(QuestObjective)

  active_character_quests.each do |cq|
    step = current_step_for(cq)
    next if step.nil?

    objectives = QuestObjective.where(
      quest_id: cq.quest_id,
      step_id: step.id,
      objective_type: "examine",
      target_type: "object"
    )

    objectives.each do |obj|
      next unless objective_matches_room?(obj, room_id)

      params = parse_parameters(obj.parameters_json)
      object_id = params["item_object_id"].to_i if params["item_object_id"].present?
      object_id = obj.target_id.to_i if object_id.to_i <= 0 && obj.target_id.to_s =~ /^\d+$/
      object_id = object_id if object_id.to_i > 0

      match_name = params["match_name"].presence || obj.target_id.to_s
      match_name = nil if match_name.to_s =~ /^\d+$/

      item_exists = if object_id.to_i > 0
                      InventoryItem.where(owner_type: "Room", owner_id: room_id, object_id: object_id).exists?
                    else
                      InventoryItem.joins(:game_object)
                                   .where(owner_type: "Room", owner_id: room_id)
                                   .where("LOWER(objects.name) LIKE ?", "%#{match_name.to_s.downcase}%")
                                   .exists?
                    end

      next if item_exists

      game_object = if object_id.to_i > 0
                      GameObject.find_by(id: object_id)
                    elsif match_name.present?
                      GameObject.where("LOWER(name) LIKE ?", "%#{match_name.to_s.downcase}%").first
                    end

      next if game_object.nil?

      InventoryItem.create!(
        owner_type: "Room",
        owner_id: room_id,
        object_id: game_object.id,
        quantity: 1
      )
    end

    visit_objectives = QuestObjective.where(
      quest_id: cq.quest_id,
      step_id: step.id,
      objective_type: "visit",
      target_type: "room"
    )

    visit_objectives.each do |obj|
      next unless objective_matches_room?(obj, room_id)

      params = parse_parameters(obj.parameters_json)
      object_id = params["on_entry_spawn_object"].to_i
      next if object_id <= 0
      next if InventoryItem.where(owner_type: "Room", owner_id: room_id, object_id: object_id).exists?

      game_object = GameObject.find_by(id: object_id)
      next if game_object.nil?

      InventoryItem.create!(
        owner_type: "Room",
        owner_id: room_id,
        object_id: game_object.id,
        quantity: 1
      )
    end
  end
end

def objective_matches_room?(objective, room_id)
  return false if room_id.nil?

  if objective.target_room_id.present?
    return false unless objective.target_room_id.to_i == room_id.to_i
  end

  params = parse_parameters(objective.parameters_json)
  if params["allowed_room_ids"].present?
    allowed = params["allowed_room_ids"].map(&:to_i)
    return false unless allowed.include?(room_id.to_i)
  end

  true
end

def journal(text)
  args = text.to_s.strip.split(" ")

  # Abandon flow: journal abandon <quest_id>
  if args.first.to_s.downcase == "abandon"
    token = args[1]
    unless token.present? && token =~ /^\d+$/
      print "Usage: journal abandon <quest_id>"
      return
    end

    quest_id = token.to_i
    cq = active_character_quests.find { |row| row.quest_id.to_i == quest_id }

    if cq.nil?
      print "You do not have that quest active."
      return
    end

    q = Quest.find_by(id: quest_id)
    quest_name = q&.name.presence || q&.quest_key.to_s || "Quest #{quest_id}"

    cq.state = "abandoned" if cq.respond_to?(:state=)
    cq.abandoned_at = Time.now if cq.respond_to?(:abandoned_at=) && CharacterQuest.column_names.include?("abandoned_at")

    cooldown_seconds = 0
    if q && q.respond_to?(:cooldown_seconds)
      cooldown_seconds = q.cooldown_seconds.to_i
    end

    if q && q.respond_to?(:repeatable?) && q.repeatable? && cooldown_seconds > 0 && cq.respond_to?(:cooldown_until=) && CharacterQuest.column_names.include?("cooldown_until")
      cq.cooldown_until = Time.now + cooldown_seconds
    end

    cq.save!

    print "You abandon: #{quest_name}"

    secs = seconds_until(cq.respond_to?(:cooldown_until) ? cq.cooldown_until : nil)
    print "You can accept it again in #{secs}s." if secs > 0
    return
  end

  # List flow: journal
  if args.empty? || args.first.to_s.strip == ""
    cqs = active_character_quests
    if cqs.empty?
      print "Your journal is empty."
      return
    end

    quest_ids = cqs.map { |row| row.quest_id.to_i }.uniq
    quests_by_id = Quest.where(id: quest_ids).to_a.each_with_object({}) { |qq, h| h[qq.id.to_i] = qq }

    print ""
    print $pastel.on_blue($pastel.bright_white($pastel.bold("                         ")))
    print $pastel.on_blue($pastel.bright_white($pastel.bold("         Journal         ")))
    print $pastel.on_blue($pastel.bright_white($pastel.bold("                         ")))
    print ""

    cqs.each do |cq|
      q = quests_by_id[cq.quest_id.to_i]
      name = q&.name.presence || q&.quest_key.to_s || "Quest #{cq.quest_id}"
      qid = cq.quest_id.to_i
      print "#{$pastel.cyan(qid.to_s)}) #{$pastel.bold(name)}"

      step = current_step_for(cq)
      if step
        step_label = "Step #{step.step_number}: #{step.name}".strip
        print "   #{$pastel.yellow(step_label)}"
      end

      if defined?(CharacterQuestObjective) && defined?(QuestObjective) && quests_table_exists?("character_quest_objectives")
        begin
          rows = CharacterQuestObjective.where(character_quest_id: cq.id).to_a
          total = rows.length
          complete = rows.count { |r| objective_completed?(r) }
          if total > 0
            obj_line = "Objectives: #{complete}/#{total}"
            print "   #{$pastel.magenta(obj_line)}"
          end
        rescue
        end
      end

      # Turn-in reminder line
      room = quest_turn_in_room(q)
      if room
        turn = "Turn-in: #{room.name}"
        cmd = "complete #{cq.quest_id}"
        print "   #{$pastel.cyan(turn)} (#{$pastel.yellow(cmd)})"
      else
        cmd = "complete #{cq.quest_id}"
        print "   #{$pastel.cyan('Turn-in:')} #{$pastel.yellow(cmd)}"
      end

      hint = "journal #{cq.quest_id}"
      print "   #{$pastel.bright_black('Details:')} #{$pastel.yellow(hint)}\n"
    end

    return
  end

  # Detail flow: journal <quest_id>
  token = args.first
  unless token.present? && token =~ /^\d+$/
    print "Usage: journal <quest_id>"
    return
  end

  quest_id = token.to_i

  cq = active_character_quests.find { |row| row.quest_id.to_i == quest_id }
  if cq.nil?
    print "You do not have that job active."
    return
  end

  q = Quest.find_by(id: quest_id)
  name = q&.name.presence || q&.quest_key.to_s || "Quest #{quest_id}"

  print ""
  print "#{$pastel.cyan(quest_id.to_s)}) #{$pastel.bold(name)} #{$pastel.green('[ACTIVE]')}"
  print q.summary.to_s if q&.respond_to?(:summary) && q.summary.present?

  step = current_step_for(cq)
  if step
    print ""
    step_line = "Current Step #{step.step_number}: #{step.name}".strip
    print $pastel.yellow(step_line)
    print "   #{step.description}" if step.respond_to?(:description) && step.description.present?
  end

  if defined?(CharacterQuestObjective) && defined?(QuestObjective) && quests_table_exists?("character_quest_objectives")
    begin
      rows = CharacterQuestObjective.where(character_quest_id: cq.id).to_a
      if rows.any?
        obj_ids = rows.map { |r| r.quest_objective_id.to_i }.uniq
        objs_by_id = QuestObjective.where(id: obj_ids).to_a.each_with_object({}) { |oo, h| h[oo.id.to_i] = oo }

        print ""
        print $pastel.magenta($pastel.bold("Objectives:"))
        rows.each do |r|
          obj = objs_by_id[r.quest_objective_id.to_i]
          label = obj&.description.presence || obj&.objective_type.to_s || "Objective #{r.quest_objective_id}"

          # Progress formatting
          cur = r.respond_to?(:current_count) ? r.current_count.to_i : nil
          tgt = obj&.respond_to?(:required_count) ? obj.required_count.to_i : nil
          done = objective_completed?(r)

          done_tag = done ? " #{$pastel.green('[DONE]')}" : ""

          if cur && tgt && tgt > 0
            prog = "(#{cur}/#{tgt})"
            print "- #{label} #{$pastel.yellow(prog)}#{done_tag}"
          else
            print "- #{label}#{done_tag}"
          end
        end
      end
    rescue
    end
  end

  print ""
  # Turn-in reminder for detail view
  room = quest_turn_in_room(q)
  if room
    turn = "Turn-in: #{room.name}"
    cmd = "complete #{quest_id}"
    print "#{$pastel.cyan(turn)} (#{$pastel.yellow(cmd)})"
  else
    cmd = "complete #{quest_id}"
    print "#{$pastel.cyan('Turn-in:')} #{$pastel.yellow(cmd)}"
  end

  abandon_cmd = "journal abandon #{quest_id}"
  print "#{$pastel.bright_black('Abandon:')} #{$pastel.yellow(abandon_cmd)}"
end

def active_character_quests
  return [] unless defined?(CharacterQuest)
  return [] unless quests_table_exists?("character_quests")

  fk = character_quest_fk_column

  CharacterQuest
    .where(fk => @player.id, state: "active")
    .order(Arel.sql("COALESCE(started_at, created_at) DESC"))
    .order(id: :desc)
    .to_a
rescue
  []
end

def objective_completion_column
  return "is_completed" if defined?(CharacterQuestObjective) &&
                           CharacterQuestObjective.column_names.include?("is_completed")
  return "is_complete" if defined?(CharacterQuestObjective) &&
                          CharacterQuestObjective.column_names.include?("is_complete")

  nil
end

def objective_completed?(row)
  col = objective_completion_column
  return false if col.nil?

  return false unless row.respond_to?(col)

  value = row.send(col)
  return true if value == true
  return false if value == false || value.nil?

  value.to_i == 1
end

def current_step_for(character_quest)
  return nil unless defined?(QuestStep)
  return nil unless quests_table_exists?("quest_steps")

  step_no = 1
  if character_quest.respond_to?(:current_step_number) && character_quest.current_step_number.present?
    step_no = character_quest.current_step_number.to_i
  end

  QuestStep.find_by(quest_id: character_quest.quest_id, step_number: step_no) ||
    QuestStep.where(quest_id: character_quest.quest_id).order(:step_number).first
rescue
  nil
end

# Helper to fetch the quest turn-in room safely
def quest_turn_in_room(quest)
  return nil if quest.nil?
  return nil unless quest.respond_to?(:start_room_id)
  rid = quest.start_room_id
  return nil if rid.nil?
  Room.find_by(id: rid)
rescue
  nil
end

def quests_table_exists?(table_name)
  ActiveRecord::Base.connection.data_source_exists?(table_name)
rescue
  false
end

def parse_parameters(parameters_json)
  return {} if parameters_json.blank?

  JSON.parse(parameters_json.to_s)
rescue JSON::ParserError
  {}
end

def character_quest_fk_column
  return :player_character_id if defined?(CharacterQuest) && CharacterQuest.column_names.include?("player_character_id")
  return :character_id if defined?(CharacterQuest) && CharacterQuest.column_names.include?("character_id")
  # Fallback to the association name if neither column is present.
  :player_character_id
end

def fetch_latest_character_quest(character_id, quest_id)
  return nil unless defined?(CharacterQuest)

  fk = character_quest_fk_column

  CharacterQuest
    .where(fk => character_id, quest_id: quest_id)
    .order(Arel.sql("COALESCE(started_at, created_at) DESC"))
    .order(id: :desc)
    .first
rescue
  nil
end

def prerequisites_pass?(quest_id)
  # If prerequisites tables aren't present, allow.
  return true unless quests_table_exists?("quest_prerequisites")

  prereqs = ActiveRecord::Base.connection.exec_query(
    "SELECT prereq_type, prereq_key, prereq_value FROM quest_prerequisites WHERE quest_id = #{ActiveRecord::Base.connection.quote(quest_id)}"
  ).to_a

  return true if prereqs.empty?

  level = @player.level.to_i

  prereqs.all? do |p|
    case p["prereq_type"].to_s
    when "level"
      level >= p["prereq_value"].to_i
    when "quest_completed"
      next true unless quests_table_exists?("character_quests")
      req_quest_id = p["prereq_value"].to_i
      row = ActiveRecord::Base.connection.select_one(
        "SELECT id FROM character_quests WHERE character_id = #{ActiveRecord::Base.connection.quote(@player.id)} AND quest_id = #{ActiveRecord::Base.connection.quote(req_quest_id)} AND state = 'completed' LIMIT 1"
      )
      row.present?
    when "flag"
      next true unless quests_table_exists?("character_flags")
      key = p["prereq_key"].to_s
      val = p["prereq_value"]
      if val.nil?
        row = ActiveRecord::Base.connection.select_one(
          "SELECT id FROM character_flags WHERE character_id = #{ActiveRecord::Base.connection.quote(@player.id)} AND flag_key = #{ActiveRecord::Base.connection.quote(key)} LIMIT 1"
        )
      else
        row = ActiveRecord::Base.connection.select_one(
          "SELECT id FROM character_flags WHERE character_id = #{ActiveRecord::Base.connection.quote(@player.id)} AND flag_key = #{ActiveRecord::Base.connection.quote(key)} AND flag_value = #{ActiveRecord::Base.connection.quote(val.to_s)} LIMIT 1"
        )
      end
      row.present?
    else
      # Unknown prereq type: be permissive.
      true
    end
  end
rescue
  true
end

def fetch_quest_rewards_summary(quest_id)
  if defined?(QuestReward)
    rows = QuestReward.where(quest_id: quest_id).to_a
    return nil if rows.empty?

    credits = rows.select { |r| r.reward_type.to_s == "credits" }.sum { |r| r.amount.to_i }
    xp = rows.select { |r| r.reward_type.to_s == "xp" }.sum { |r| r.amount.to_i }

    parts = []
    parts << "#{credits} credits" if credits > 0
    parts << "#{xp} xp" if xp > 0

    return parts.any? ? parts.join(", ") : nil
  end

  return nil unless quests_table_exists?("quest_rewards")

  rows = ActiveRecord::Base.connection.exec_query(
    "SELECT reward_type, amount FROM quest_rewards WHERE quest_id = #{ActiveRecord::Base.connection.quote(quest_id)}"
  ).to_a

  return nil if rows.empty?

  credits = rows.select { |r| r["reward_type"].to_s == "credits" }.sum { |r| r["amount"].to_i }
  xp = rows.select { |r| r["reward_type"].to_s == "xp" }.sum { |r| r["amount"].to_i }

  parts = []
  parts << "#{credits} credits" if credits > 0
  parts << "#{xp} xp" if xp > 0

  parts.any? ? parts.join(", ") : nil
rescue
  nil
end
