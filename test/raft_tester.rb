require 'rubygems'
require 'bud'
require 'test/unit'
require 'raft'

class RealRaft
  include Bud
  include Raft

  state do
    table :states, [:timestamp] => [:state, :term]
  end

  bloom do
    states <= (st.current_state * st.current_term).pairs {|s, t| [budtime, s.state, t.term]}
  end
end

class RaftTester < Test::Unit::TestCase
  def teardown
    @servers.each {|s| s.stop} if @servers
  end
  
  # create a cluster of servers with addresses starting with localhost:54321
  def create_cluster(num_servers)
    cluster = []
    (1..num_servers).to_a.each do |num|
      cluster << ["127.0.0.1:#{54320+num}"]
    end
    return cluster
  end
  
  def start_servers(num_servers, options = {})
    cluster = create_cluster(num_servers)
    @servers = []
    (1..num_servers).to_a.each do |num|
      instance = RealRaft.new(:port => 54320 + num)
      instance.set_cluster(cluster)
      instance.set_timeout(options[:time_out][0], options[:time_out][1]) if options[:time_out]
      instance.run_bg
      @servers << instance
    end
  end
  
  def get_state(server)
    server.st.current_state.values[0][0]
  end

  def get_term(server)
    server.st.current_term.values[0][0]
  end
  
  def get_states(server)
    server.states.values.map {|v| v[0]}
  end
end
