class Android < Tribe::Actor
	def self.x=(x)
		@x = x
	end
	def self.y=(y)
		@y = y
	end
	def self.z=(z)
		@z = z
	end
	def self.name=(name)
	end


	private

	def on_initialize(event)
		timer!(1, :timer, 'hello once')
	end

	def on_timer(event)
		puts "Actor (#{identifier}) ONE_SHOT: #{event.data}"
	end

	def on_start(event)
	end

	def on_shutdown(event)
	end
end
