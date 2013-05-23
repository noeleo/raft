class Logs
  def initialize(logs)
    @logs = logs.inspected
    puts @logs
  end
  
  def contains_index(index)
    logs.keys.map{|k| k[0]}.include?(index)
  end
  
  def term(index)
    logs.select{|l| l.values.select{|v| v[0] == index}.first
  end
  
  def entry(index)
    logs.values[index][1]
  end
  
  def is_committed(index)
    logs.values[index][2]
  end
end
