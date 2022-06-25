require 'active_record'
require 'bcrypt'

class User < ActiveRecord::Base
  include BCrypt

  has_many :player_characters

  def password
    @password ||= Password.new(self.encrypted_password)
  end

  def password=(new_password)
    @password = Password.create(new_password)
    self.encrypted_password = @password
  end

  def self.get_logged_in_users
    who = self.where(logged_in: 1).joins(:player_characters).select('*').order('users.current_login_at DESC').all
  end
end

