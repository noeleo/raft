module LoggerProtocol
  state do
    interface :input, :get_status , [] => [:ok]
    # if replace_index is not nil, we insert at replace_index and remove all following entries
    interface :input, :add_log, [] => [:term, :entry, :replace_index]
    interface :input, :commit_logs_before, [] => [:index]
    interface :input, :remove_uncommitted_logs, [] => [:ok]
    interface :output, :status, [] => [:last_index, :last_term, :last_committed]
    interface :output, :added_log_index, [] => [:index]
    interface :output, :committed_logs, [:index] => [:entry]
  end
end

module Logger
  include LoggerProtocol

  state do
    table :logs, [:index] => [:term, :entry, :is_committed]
    scratch :last_index, [] => [:index]
    scratch :last_term, [] => [:term]
    scratch :last_committed, [] => [:index]
    
    scratch :single_log, add_log.schema
    scratch :possible_update_points, [:index]
  end

  bootstrap do
    logs <= [[0, 0, nil, true]]
  end

  bloom :remove_logs do
    logs <- (remove_uncommitted_logs * logs).pairs do |r, l|
      l unless l.is_committed
    end
  end

  bloom :set_metadata do
    temp :last_log <= logs.argmax([], :index)
    last_index <= last_log {|e| [e.index]}
    last_term <= last_log {|e| [e.term]}
    temp :committed <= logs {|l| l if l.is_committed}
    last_committed <= committed.argmax([], :index) {|e| [e.index]}
  end

  bloom :add do
    single_log <= add_log.argagg(:max, [], :entry)
    # remove all logs after the one we are inserting
    logs <- (single_log * logs).pairs do |a, l|
      l if a.replace_index and l.index >= a.replace_index
    end
    logs <+ (single_log * last_index).pairs do |a, i|
      [a.replace_index ? a.replace_index : i.index + 1, a.term, a.entry, false]
    end
    added_log_index <= (single_log * last_index).pairs do |a, i|
      [a.replace_index ? a.replace_index : i.index + 1]
    end
  end
  
  bloom :commit do
    # only update the logs that are not going to be deleted
    possible_update_points <= last_index {|i| [i.index]}
    possible_update_points <= single_log {|a| [a.replace_index-1] if a.replace_index}
    temp :update_before <= possible_update_points.argmin([], :index)
    logs <+- (commit_logs_before * update_before * last_committed * logs).pairs do |b, u, c, l|
      [l.index, l.term, l.entry, true] if l.index <= u.index and l.index <= b.index and l.index > c.index
    end
    committed_logs <= (commit_logs_before * update_before * last_committed * logs).pairs do |b, u, c, l|
      [l.index, l.entry] if l.index <= u.index and l.index <= b.index and l.index > c.index
    end
  end

  bloom :output do
    status <= (get_status * last_index * last_term * last_committed).combos do |g, i, t, c|
      [i.index, t.term, c.index]
    end
  end
end
