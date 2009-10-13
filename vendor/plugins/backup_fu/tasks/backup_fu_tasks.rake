require 'fileutils'

$:.unshift(File.dirname(__FILE__) + '/../lib')
require 'backup_fu'
$backup_fu_path = File.join(File.dirname(__FILE__), '..')

desc "Dumps the database and backs it up remotely to Amazon S3. (task added by: backup_fu)"
task :backup do
  b = BackupFu.new
  b.backup
end

namespace :backup_fu do
  
  desc "Copies over the example backup_fu.yml file to config/"
  task :setup do
    target = File.join($backup_fu_path, 'config', 'backup_fu.yml.example')
    destination = File.join(RAILS_ROOT, 'config', 'backup_fu.yml')
    if File.exist?(destination)
      puts "\nTarget file: #{destination}\n ... already exists.  Aborting.\n\n"
    else
      FileUtils.cp(target, destination)
      puts "\nExample backup_fu.yml copied to config/.  Please edit this file before proceeding.\n\nSee 'rake -T backup_fu' for more commands.\n\n"
    end
  end
  
  desc "Dumps the database locally.  Does *not* upload to S3."
  task :dump do
    b = BackupFu.new
    b.dump
  end

  desc "Same as 'rake backup'. Dumps the database and backs it up remotely to Amazon S3."
  task :backup do
    b = BackupFu.new
    b.backup
  end

  desc "Backs up both the DB and static files."
  task :all do
    b = BackupFu.new

    begin
      b.backup
    rescue Exception => e
      puts "[#{Time.now}] Error backing up database dump."  
    end

    begin
      b.backup_static
    rescue Exception => e
      puts "[#{Time.now}] Error backing up static files."        
    end
    
  end
  
  desc "Clean up old backups. By default 5 backups are kept (you can change this with with keep_backups key in config/backup_fu.yml)."
  task :cleanup do
    b = BackupFu.new
    b.cleanup
  end
  
  namespace :static do

    desc "Tars and gzips static application files locally.  Does *not* upload to S3."
    task :dump do
      b = BackupFu.new
      b.dump_static
    end
    
    desc "Backups up static files to Amazon S3. For configuration see the backup_fu README."
    task :backup do
      b = BackupFu.new
      b.backup_static
    end
  end
  
  
end
