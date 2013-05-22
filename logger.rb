require 'rubygems'
require 'bud'

module LoggerProtocol
  state do
    interface :input, :get_status , [] => [:ok]
    interface :input, :add_log, [] => [:term, :entry, :is_committed]
    interface :input, :commit_log, [] => [:index]
    interface :input, :remove_logs_after, [] => [:index]
    interface :input, :remove_uncommitted, [] => [:ok]
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
  
  bloom :remove_logs do
    logs <- (remove_logs_after * logs).pairs do |r, l|
      l if l.index > r.index
    end
    logs <- (remove_uncommitted * logs).pairs do |r, l|
      l unless l.is_committed
    end
  end
  
  bloom :set_metadata do
    last_index <= logs.argmax([:index], :index) {|e| [e.index]}
    last_term <= logs.argmax([:index], :index) {|e| [e.term]}
    temp :committed <= logs {|l| l if l.is_committed}
    last_committed <= committed.argmax([:index], :index) {|e| [e.index]}
  end
  
  bloom :commit do
    logs <+- (commit_log * logs).pairs(:index => :index) do |c, l|
      [l.index, l.term, l.command, true]
    end
  end
  
  bloom :add do
    logs <= (add_log * last_index).pairs do |a, i|
      [i.index + 1, a.term, a.entry, a.is_committed]
    end
  end
  
  bloom :output do
    status <= (last_index * last_term * last_committed).combos do |i, t, c|
      [i.index, t.term, c.index]
    end
  end
end
