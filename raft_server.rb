require 'rubygems'
require 'bud'

require 'src/raft'

class RaftServer
  include Bud
  include Raft
end

port = ARGV[0].to_i
cluster = ARGV[1..ARGV.length]
server = RaftServer.new(cluster, :port => port)
