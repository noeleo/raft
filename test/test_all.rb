# runs all tests in the test directory

test_files = Dir.entries(File.dirname(__FILE__)).select do |file|
  file =~ /^test_.*.rb$/
end
test_files.delete(File.basename(__FILE__))
test_files = test_files.map {|t| File.dirname(__FILE__) + '/' + t}
test_files.each { |file| require file }
