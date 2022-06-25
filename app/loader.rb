require 'active_record'
require 'active_enum'
require 'totem'
require '~/lands-server/lib/db_setup'
require '~/lands-server/lib/active_enum_defs'
require 'awesome_print'
require 'tribe'
require 'bcrypt'
require '~/lands-server/model/user'
require '~/lands-server/model/player_character'
require '~/lands-server/model/npc'
require '~/lands-server/model/npc_saying'
require '~/lands-server/model/npc_movement'
require '~/lands-server/model/room'
require '~/lands-server/model/room_saying'
require '~/lands-server/model/event.rb'
require '~/lands-server/model/prop'
require '~/lands-server/model/creature'
require '~/lands-server/model/creature_instance'
require '~/lands-server/model/ship'
require '~/lands-server/model/custom_command'

Dir[File.join(__dir__, 'lib', '*.rb')].each { |file| require file }
Dir[File.join(__dir__, 'model', '*.rb')].each { |file| require file }

User.connection
PlayerCharacter.connection

