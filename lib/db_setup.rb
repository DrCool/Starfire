require 'active_record'

ActiveRecord::Base.establish_connection(
  adapter:  'mysql2',
  host:     'localhost',
  username: 'root',
  password: '',
  database: 'lands_game',
  pool: 50
)
