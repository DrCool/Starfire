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


$LOAD_PATH.unshift(File.expand_path('../lib', __dir__)) unless $LOAD_PATH.include?(File.expand_path('../lib', __dir__))

require 'lands'
require 'world'
require_relative '../model/npc'
require_relative '../model/shop'
require_relative '../model/shop_inventory'

require 'ostruct'
require 'socket'
require 'fcntl'
require 'open3'
require 'json'

require 'pastel'
require 'db_setup'
require 'awesome_print'
require 'active_record'
require 'active_enum'
require_relative '../lib/active_enum_defs'
require_relative '../lib/event_processor'
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
  ActiveRecord::Base.connection_pool.flush!
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
    World::Manager.repopulate_creatures
    init_global_creature_respawner
    init_ship_mover
    init_shop_restock
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

  def init_ship_mover
    puts "Starting ship mover"
    # Load all ships from Ship model
    ships = Ship.all.where(is_automated: true)

    # Start global ShipMover for moving autonomous ships like the Dalcrynn
    $mover = World::ShipMover.new(ships)
    Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        loop do
          sleep 1
          $mover.process_queue
        end
      end
    end
  end

  def init_shop_restock
    puts "Starting shop restocker"
    Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        loop do
          sleep 60
          restock_shops
        end
      end
    end
  end

  def restock_shops
    Shop.find_each do |shop|
      interval = shop.restock_interval_seconds.to_i
      interval = 1800 if interval <= 0

      ShopInventory.where(shop_id: shop.id).find_each do |entry|
        next if entry.stock.to_i >= entry.stock_max.to_i

        last_restock = entry.last_restock_at || Time.at(0)
        next if Time.now - last_restock < interval

        min = entry.restock_min.to_i
        max = entry.restock_max.to_i
        min = 1 if min <= 0
        max = min if max < min

        amount = rand(min..max)
        new_stock = [entry.stock.to_i + amount, entry.stock_max.to_i].min
        entry.update!(stock: new_stock, last_restock_at: Time.now)
      end
    end
  end

  def start_docker_container
    puts "Starting RubyRemote Server"
    # This starts the docker container "lands-code-runner", listening on port 2200

    @ruby_server_thread = Thread.new do
      ENV['DOCKER_HOST'] = 'tcp://docker:2375'
      #result = system("docker run --read-only -d --network=lands-server_default -p 2200:2200 --name lands-code-runner lands-code-runner")
      result = system("docker compose run --read-only -d --network=lands-server_default -p 2200:2200 --name lands-code-runner lands-code-runner")
      puts "Started container: #{result}"
    end
  end


end

Init.new.start
