class Log
  def initialize(log)
    @log = log
  end
  
  def term
    @log[1]
  end
  
  def entry
    @log[2]
  end
  
  def is_committed
    @log[3]
  end
end

class Logs
  def initialize(logs)
    @logs = logs.to_a
    @logs.sort_by!{|l| l[0]}
  end
  
  def ==(other_object)
    @logs == other_object.logs
  end
  
  def logs
    @logs
  end
  
  def contains_index(index)
    @logs[index] != nil
  end
  
  def index(index)
    Log.new @logs.select{|l| l[0] == index}.first
  end
end
