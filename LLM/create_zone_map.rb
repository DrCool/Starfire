require_relative 'zone_preview_builder'
require_relative 'call_ollama'
require_relative '../lib/map'
require_relative 'map_graph'

def create_zone_map
  # Prepare the first-pass prompt to generate the zone with an LLM
  # Load CREATE_ZONE.md into a variable
#   prompt = File.read(File.join(File.dirname(__FILE__), '.', 'CREATE_ZONE.md'))
#
#   data = [
#     {
#       name: "# Rooms:         ",
#       type: FIELD_TYPE_INTEGER,
#       value: {
#         max_display_chars: 4,
#         existing_value: 40,
#       }
#     },
#     {
#       name: "Normal:          ",
#       type: FIELD_TYPE_BOOLEAN,
#       value: {
#         existing_value: false,
#       }
#     },
#     {
#       name: "City Core:       ",
#       type: FIELD_TYPE_BOOLEAN,
#       value: {
#         existing_value: true,
#       }
#     },
#     {
#       name: "Hub-and-Spokes:  ",
#       type: FIELD_TYPE_BOOLEAN,
#       value: {
#         existing_value: false,
#       }
#     },
#     {
#       name: "Dense Maze:      ",
#       type: FIELD_TYPE_BOOLEAN,
#       value: {
#         existing_value: false,
#       }
#     },
#     {
#       name: "Multiple Levels: ",
#       type: FIELD_TYPE_BOOLEAN,
#       value: {
#         existing_value: false,
#       }
#     },
#     {
#       name: " SAVE ",
#       type: FIELD_TYPE_SAVE
#     },
#     {
#       name: " CANCEL ",
#       type: FIELD_TYPE_CANCEL
#     }
#   ]
#   d = form(data)
#   return if d.nil?
#
#   print "Generating zone map with LLM..."
#
#   # [{:name=>"# Rooms:         ", :type=>1, :value=>{:max_display_chars=>4, :existing_value=>"35"}}, {:name=>"Normal:          ", :type=>2, :value=>{:existing_value=>false}},
#   # {:name=>"City Core:       ", :type=>2, :value=>{:existing_value=>false}}, {:name=>"Hub-and-Spokes:  ", :type=>2, :value=>{:existing_value=>true}}, {:name=>"Dense Maze:      ",
#   # :type=>2, :value=>{:existing_value=>false}}, {:name=>"Multiple Levels: ", :type=>2, :value=>{:existing_value=>false}}, {:name=>" SAVE ", :type=>3}, {:name=>" CANCEL ", :type=>4}]
#
#   room_count = d[0][:value][:existing_value].to_i
#   modifications = "- Maze-like: corridors + branches + at least 2 loops (cycle length >= 4).
# - Include at least 6 dead ends (rooms with degree 1).
# - Include at least 4 junctions (rooms with degree >= 3).
# - Include 0 to 3 vertical edges total. If you include any, label them with \"kind: 'vertical'\".
# - Create two backbone corridors of length 6–9 each.
# - Connect them with 2–4 bridges (edges between the backbones).
# - Attach 6–10 spur rooms total.
# - Include 2 loops not counting the bridges.
# "
#   self_check = "Ensure there are at least 6 dead-ends and at least 4 junctions."
#   if d[2][:value][:existing_value] == true
#            modifications = "- Create one main boulevard corridor of length 10–14 (a single simple path).
# - Create 2–4 cross-streets (secondary corridors) of length 4–7 each that connect to the boulevard at different points.
# - Attach 8–12 alley spurs (dead-end chains of length 1–3) branching off the boulevard or cross-streets.
# - Include 2–3 loops formed by cross-street connections (not by adding random long-range edges).
# - Include 6–10 dead ends.
# - Include 4–6 junctions (degree ≥ 3), mostly on the boulevard/cross-streets (not in deep alleys).
# - Vertical edges: 0–2, and if present they should connect a boulevard/cross-street node to an alley node (like a stairwell/skybridge access).
# "
#             self_check = "Ensure there are at least 6 dead-ends, at least 2 cross streets, at least 4 junctions, and at least 8 alley spurs."
#          elsif d[3][:value][:existing_value] == true
#            modifications = "- Create one central hub room (degree 4–6) that serves as the plaza for the map.
# - Create 4–6 spokes (corridors) of length 3–7 radiating from the hub (spokes should not connect to each other directly near the hub).
# - Add 1–2 ring paths: connect the outer portions of 2–4 spokes together to form 1–2 large loops (cycle length ≥ 6).
# - Add 6–10 dead ends by placing small cul-de-sacs off the spokes (length 1–2).
# - Keep the hub as the highest-degree node in the entire graph.
# - Vertical edges: 0–2, and if present one should be on a spoke near the outer ring (like stairs to an overlook).
# "
#            self_check = "Ensure there are at least 6 dead-ends, at least 4 spokes, and 1 or 2 ring paths."
#          elsif d[4][:value][:existing_value] == true
#            min_rooms = room_count + 10
#            max_rooms  = room_count + 14
#            modifications = "- Aim for a dense, twisty maze: total edges should be {min_rooms} to {max_rooms}.
# - Include 3–5 loops with varied lengths (4–10).
# - Include 3–6 dead ends.
# - Include 8–12 junctions (degree ≥ 3), but avoid any single “super hub” (no node degree > 5).
# - Prefer short connections that create local complexity (avoid long-range edges that jump across the map).
# - Vertical edges: 1–3 recommended; treat them as maintenance ladders that create “shortcut layers.”
# "
#            modifications = modifications.gsub('{min_rooms}', min_rooms.to_s).gsub('{max_rooms}', max_rooms.to_s)
#            self_check = "Ensure there are at least 3 dead-ends and at least 8 junctions."
#          elsif  d[5][:value][:existing_value] == true
# #            modifications = "- Create at least 3 levels (z-coordinates).
# # - Distribute rooms roughly evenly across levels.
# # - Include vertical connections (edges) between levels: at least 2, up to 5 total.
# # - Each level should have its own distinct layout style (e.g., one level maze-like, another hub-and-spokes, another city core).
# # - Ensure there are multiple paths to reach key areas by combining horizontal and vertical connections.
# # - Include at least 2 loops that span multiple levels.
# # "
#             modifications = "- Create two layers:
# - A ground layer (most rooms)
# - An upper/lower layer connected via vertical edges
# - Include 2–3 vertical edges total (required) that connect key junctions between layers.
# - Build two medium corridors (length 7–10 each) that represent the primary routes on each layer.
# - Add 2–4 loops, and at least one loop must use a vertical edge (a loop that goes up/down and returns).
# - Include 4–8 dead ends (dead ends are good for balconies, service doors, locked lifts).
# - Include 5–8 junctions (degree ≥ 3), and ensure at least two junctions are on different z-levels (connected by vertical edges).
# - Avoid putting all vertical edges in one area; spread them out."
#           self_check = "Ensure there are at least 4 dead-ends at least 5 junctions."
#          end
#
#   prompt.gsub!('{num_rooms}', room_count.to_s)
#   prompt.gsub!('{modifications}', modifications)
#   prompt.gsub!('{self_check}', self_check)
#
#   result = call_ollama(prompt)
#
#   json_text = result
#   json_text.gsub!('\\n', "\n") if json_text.include?('\\n')
#   json_text.gsub!('\\"', '"') if json_text.include?('\\"')
#   print json_text
#
#   if json_text.include?("\n\n")
#     parts = json_text.split("\n\n")
#     json_text = parts.last.strip
#   end
#   if json_text.include?("\n\n")
#     parts = json_text.split("\n\n")
#     json_text = parts.first.strip
#   end
#
#   if json_text.include?("\n```\n")
#     parts = json_text.split("\n```\n")
#     json_text = parts[1].strip
#     if json_text.include?("\n```\n")
#       parts = json_text.split("\n```\n")
#       json_text = parts[0].strip
#     end
#   end
#
#   begin
#     data = JSON.parse(json_text)
#   rescue JSON::ParserError => e
#     print "JSON parse error: #{e.message}\n"
#     return
#   end

  data = generate_starfire_map(
    type: :city_core,
    room_count: 44
  )

  rooms = ZonePreviewBuilder.build_preview_rooms_from_llm_json!(
    data,
    zone_id: 999,        # any temp zone id for preview
    created_by: 1,
    start_x: -100,
    start_y: -100,
    start_z: -100
  )

  # Pick a “current room” for preview; typically rooms.first (R001).
  current_room = rooms.first

  show_map rooms, current_room.id, @screen_params
end