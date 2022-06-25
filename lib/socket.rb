#!/usr/bin/env ruby
# encoding: utf-8

#        +---------------+
#        |  Future-Zone  |
#        +---------------+------------------------+
#        |                                        |
#        | A telnet multiplayer game written by   |
#        | Aaron McMahon                          |
#        |                                        |
#        | First started in 1994                  |
#        +----------------------------------------+
#        | Modernized starting in December 2021   |
#        +----------------------------------------+

$LOAD_PATH << '.'
require 'lands'
require 'world'
require '../model/npc'

require 'socket'
require 'fcntl'
require 'open3'
require 'json'

require 'pastel'
require 'db_setup'
require 'awesome_print'
require 'active_record'
require 'active_enum'
require '../lib/active_enum_defs'
require '../lib/event_processor'
Thread.abort_on_exception = true

$pastel = Pastel.new

# Constants
FIELD_TYPE_STRING = 0
FIELD_TYPE_INTEGER = 1
FIELD_TYPE_BOOLEAN = 2
FIELD_TYPE_SAVE = 3
FIELD_TYPE_CANCEL = 4

class KEY
  def self.UP; 0; end
  def self.DOWN; 1; end
  def self.LEFT; 2; end
  def self.RIGHT; 3; end
  def self.ENTER; 4; end
  def self.ESC; 5; end
  def self.DELETE; 6; end
  def self.SPACE; 7; end
end

class String
  def pad
    " " + self + " "
  end
end

$online_players = []

class Init
  ActiveRecord::Base.clear_active_connections!
  include World
  World::Manager.logout_all_players
  World::Manager.instantiate_npcs

  def notify_room(from_player, text, x, y, z)
    $online_players.each do |player|
      if player.present? && player.x == from_player.x && player.y == from_player.y && player.z == from_player.z
        player.notify(text)
      end
    end
  end

  def start
    init_global_creature_respawner
    #start_docker_container

    server = TCPServer.open(2000)
    puts $pastel.bright_green("Listening on port 2000")

    begin
      loop {
        thread = Thread.start(server.accept) do |client|
          op = OnlinePlayers.new(client, thread)
          $online_players << op
          thread[:op] = op
          thread[:q] = []
          thread[:event_q] = []
          sock_domain, remote_port, remote_hostname, remote_ip = client.peeraddr

          begin
            Lands.new.start_game(client)
          rescue IOError
            World::Manager.logout_player(op.player)
            thread.exit
          end
          client.close
        end

        # List all threads:    Thread.list.each {|thread| ap thread }
        # Get current thread:  Thread.current
      }
    rescue Interrupt => e
      World::Manager.logout_all_players
      exit(0)
    end
  end

  def init_global_creature_respawner
    puts "Starting creature spawner"
    # Start global EventProcessor for respawning creatures
    $spawner = World::EventProcessor.new
    Thread.new do
      loop do
        sleep 1
        $spawner.process_queue
      end
    end
  end

  def start_docker_container
    puts "Starting RubyRemote Server"
    # This starts the docker container "ruby-server", listening on port 2200

    @ruby_server_thread = Thread.new do
      result = system( "docker run --read-only -it -p 2200:2200 ruby-server" )
      puts "RubyRemote server running: #{result}"
    end
  end


end

Init.new.start
