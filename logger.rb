require 'rubygems'
require 'bud'

module LoggerProtocol
  state do
    interface :input, :get_status , [] => [:ok]
    interface :input, :add_log, [] => [:term, :entry]
    interface :input, :commit_logs_before, [] => [:index]
    interface :input, :remove_logs_after, [] => [:index]
    interface :input, :remove_uncommitted_logs, [] => [:ok]
    interface :output, :status, [] => [:last_index, :last_term, :last_committed]
  end
end

module Logger
  include LoggerProtocol

  state do
    table :logs, [:index] => [:term, :entry, :is_committed]
    scratch :last_index, [] => [:index]
    scratch :last_term, [] => [:term]
    scratch :last_committed, [] => [:index]
  end
  
  bootstrap do
    logs <= [[0, 0, nil, true]]
  end
  
  bloom :remove_logs do
    logs <- (remove_logs_after * logs).pairs do |r, l|
      l if l.index >= r.index
    end
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
    temp :single_log <= add_log.argagg(:choose, [], :term)
    logs <= (single_log * last_index).pairs do |a, i|
      [i.index + 1, a.term, a.entry, false]
    end
  end
  
  bloom :commit do
    logs <+- (commit_logs_before * logs).pairs do |c, l|
      [l.index, l.term, l.entry, true] if l.index <= c.index
    end
  end
  
  bloom :output do
    status <= (get_status * last_index * last_term * last_committed).combos do |g, i, t, c|
      [i.index, t.term, c.index]
    end
  end
end
