require 'rubygems'
require 'bud'

module Raft

  state do
    channel :request_vote, [:@dest, :from]
    channel :append_entries, [:@dest, :from, :entry]
  end

  bootstrap do
  end

  bloom do
  end
end