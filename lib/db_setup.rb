require 'logger'
logger = Logger.new(STDOUT)
logger.info "Attempting to establish DB connection..."

begin
  ActiveRecord::Base.establish_connection(
    adapter:         'mysql2',
    host:            'localhost',
    port:            3306,
    username:        'root',
    password:        '',
    database:        'lands_game',
    pool:            50,
    connect_timeout: 5
  )
  logger.info "DB connection established."
rescue => e
  logger.error "DB connection error: #{e.message}"
end