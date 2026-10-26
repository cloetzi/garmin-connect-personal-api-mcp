# frozen_string_literal: true

require "minitest/test_task"
require "rubocop/rake_task"

Minitest::TestTask.create(:test) do |task|
  task.test_globs = ["test/**/*_test.rb"]
  task.warning = false
end

RuboCop::RakeTask.new

task default: %i[rubocop test]
