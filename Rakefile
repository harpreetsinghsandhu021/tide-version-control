require "rake/testtask"

# Define a Rake task specifically designed for running tasks
Rake::TestTask.new do |task|
  # Set the pattern for finding test files
  task.libs << "test"
  task.pattern = "test/**/*_test.rb"
end

# Define a default task that defines on the 'test' task
# When rake is run without arguments, it will execute this test task
task :default => :test