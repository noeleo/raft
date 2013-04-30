require 'rubygems'
require 'bud'

module RaftProtocol
  state do
    interface input, :add_log, [:log]
    interface output, :query_log, [:log]
  end
end