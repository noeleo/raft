require 'rubygems'
require 'bud'

require 'raft'

# run with
# ruby -I/[path to raft directory] -I. test_raft.rb

class RealRaft
  include Bud
  include Raft
end
