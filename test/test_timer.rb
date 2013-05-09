require 'rubygems'
require 'bud'

require 'progress_timer'

# run with
# ruby -I/[path to raft directory] -I. test_timer.rb

class RealTimer
  include Bud
  include ProgressTimer
end

class TestTimer < Test::Unit::TestCase
  def single_workload(fd)
    fd.sync_do { fd.pipe_in <+ [ ["localhost:54322", "localhost:54321", 3, "qux"] ] }
  end

  def multiple_workload(fd1, fd2, fd3, fd4)
    fd1.sync_do { fd1.pipe_in <+ [ ["localhost:12345", "localhost:12341", 3, "a"] ] }
  end

  def test_alarm_going_off
    timer = RealTimer.new
    timer.run_bg

    sender_instance = FC.new(:port => 54321)
    receiver_instance = FC.new(:port => 54322)

    sender_instance.run_bg
    receiver_instance.run_bg
    single_workload(sender_instance)
    4.times {receiver_instance.sync_do}
    receiver_instance.sync_do do
      receiver_instance.timestamped.each do |t|
        receiver_instance.timestamped.each do |t2|
          if t.ident < t2.ident
            assert(t.time < t2.time)
          end
        end
      end
      assert_equal(4, receiver_instance.timestamped.length)
    end
  end

  def test_fifo_multiple_senders
    sender1 = FC.new(:port => 12341)
    sender2 = FC.new(:port => 12342)
    sender3 = FC.new(:port => 12343)
    sender4 = FC.new(:port => 12344)
    receiver = FC.new(:port => 12345)

    sender1.run_bg
    sender2.run_bg
    sender3.run_bg
    sender4.run_bg
    receiver.run_bg
    multiple_workload(sender1, sender2, sender3, sender4)

    16.times {receiver.sync_do}
    receiver.sync_do do
      receiver.timestamped.each do |t1|
        receiver.timestamped.each do |t2|
          # if these are from the same source, lower idents should happen earlier
          if t1.src == t2.src and t1.ident < t2.ident
            assert(t1.time < t2.time)
          end
        end
      end
      assert_equal(16, receiver.timestamped.length)
    end
  end

end