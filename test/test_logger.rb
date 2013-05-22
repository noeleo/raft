require 'rubygems'
require 'bud'
require 'test/unit'

require 'logger'

class RealLogger
  include Bud
  include Logger

  state do
  end

  bloom do
  end
end

class TestLogger < Test::Unit::TestCase
  def setup
    @logger = RealLogger.new
    @logger.run_bg
  end
  
  def teardown
    @logger.stop
  end
end
