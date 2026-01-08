class Quest < ActiveRecord::Base
  self.table_name = :quests

  def repeatable?
    ActiveRecord::Type::Boolean.new.cast(self[:repeatable])
  end

end
