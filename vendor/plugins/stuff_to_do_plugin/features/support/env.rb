# Sets up the Rails environment for Cucumber
ENV["RAILS_ENV"] = "test"

# Allows loading of an environment config based on the environment
redmine_root = ENV["REDMINE_ROOT"] || File.dirname(__FILE__) + "/../../../../.."
require File.expand_path(redmine_root + "/config/environment")
require 'cucumber/rails/world'
Cucumber::Rails.use_transactional_fixtures

require 'webrat/rails'

# Comment out the next two lines if you're not using RSpec's matchers (should / should_not) in your steps.
require 'cucumber/rails/rspec'
require 'webrat/rspec-rails'

require 'ruby-debug'

# require the entire app if we're running under coverage testing,
# so we measure 0% covered files in the report
#
# http://www.pervasivecode.com/blog/2008/05/16/making-rcov-measure-your-whole-rails-app-even-if-tests-miss-entire-source-files/
if defined?(Rcov)
  all_app_files = Dir.glob('{app,lib}/**/*.rb')
  all_app_files.each{|rb| require rb}
end
