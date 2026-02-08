require_relative 'zone_preview_builder'
require_relative 'call_ollama'
require_relative '../lib/map'
require_relative 'map_graph'

def create_zone_map
  data = generate_starfire_map(
    type: :city_core,
    room_count: 44
  )

  rooms = ZonePreviewBuilder.build_preview_rooms_from_llm_json!(
    data,
    zone_id: 999,        # temp zone id for preview
    created_by: 1,
    start_x: -100,
    start_y: -100,
    start_z: -100
  )

  ap rooms
  ap rooms.length

  # Pick a “current room” for preview; typically rooms.first (R001).
  current_room = rooms.first

  show_map rooms, current_room.id, @screen_params

  # Put player in the first room for testing


end