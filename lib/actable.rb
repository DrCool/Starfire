class Lands
  module Actable
    def process_event(event)
      ActiveRecord::Base.connection_pool.with_connection do
        puts "GETTING CONNECTION FROM POOL"
        super
      end
    end
  end
end

