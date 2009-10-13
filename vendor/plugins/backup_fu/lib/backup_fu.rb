require 'yaml'
require 'active_support'
require 'net/ftp'

class BackupFuConfigError < StandardError; end
class FtpConnectError < StandardError; end

class BackupFu
  
  def initialize
    db_conf = YAML.load_file(File.join(RAILS_ROOT, 'config', 'database.yml')) 
    @db_conf = db_conf[RAILS_ENV].symbolize_keys
    fu_conf = YAML.load_file(File.join(RAILS_ROOT, 'config', 'backup_fu.yml'))
    @fu_conf = fu_conf[RAILS_ENV].symbolize_keys
    @fu_conf[:mysqldump_options] ||= '--complete-insert --skip-extended-insert'
    @verbose = !@fu_conf[:verbose].nil?
    @timestamp = datetime_formatted
    @fu_conf[:keep_backups] ||= 5
    check_conf
    create_dirs
  end
  
  def dump
    host, port, password = '', '', ''
    if @db_conf.has_key?(:host) && @db_conf[:host] != 'localhost'
      host = "--host=#{@db_conf[:host]}"
    end
    if @db_conf.has_key?(:port)
      port = "--port=#{@db_conf[:port]}"
    end
    if @db_conf.has_key?(:password) && !@db_conf[:password].blank?
      password = "--password=#{@db_conf[:password]}"
    end
    full_dump_path = File.join(dump_base_path, db_filename)
    case @db_conf[:adapter]
    when 'postgresql'
      cmd = niceify "PGPASSWORD=#{password} #{dump_path} --user=#{@db_conf[:username]} --host=#{host} --port=#{port} #{@db_conf[:database]} > #{full_dump_path}"
    when 'mysql'
      cmd = niceify "#{dump_path} #{@fu_conf[:mysqldump_options]} #{host} #{port} --user=#{@db_conf[:username]} #{password} #{@db_conf[:database]} > #{full_dump_path}"
    end
    puts cmd if @verbose
    `#{cmd}`

    if !@fu_conf[:disable_tar_gzip]
      
      tar_path = File.join(dump_base_path, db_filename_tarred)

      # TAR it up
      cmd = niceify "tar -cf #{tar_path} -C #{dump_base_path} #{db_filename}"
      puts "\nTar: #{cmd}\n" if @verbose
      `#{cmd}`

      # GZip it up
      cmd = niceify "gzip -f #{tar_path}"
      puts "\nGzip: #{cmd}" if @verbose
      `#{cmd}`
    end
    
  end
  
  def backup
    dump
    establish_ftp_connection
    
    file = final_db_dump_path()
    puts "\nBacking up to FTP server: #{file}\n" if @verbose
    
    @ftp.put file
  end
  
  ## Static-file Dump/Backup methods
  
  def dump_static
    if !@fu_conf[:static_paths]
      raise BackupFuConfigError, 'No static paths are defined in config/backup_fu.yml.  See README.'
    end
    @paths = @fu_conf[:static_paths].split(' ')
    path_num = 0
    @paths.each do |p|
      if p.first != '/'
        # Make into an Absolute path:
        p = File.join(RAILS_ROOT, p)
      end
      
      puts "Static Path: #{p}" if @verbose
      if path_num == 0
        tar_switch = 'c'  # for create
      else
        tar_switch = 'r'  # for append
      end
      
      # TAR
      cmd = niceify "tar -#{tar_switch}f #{static_tar_path} #{p}"
      puts "\nTar: #{cmd}\n" if @verbose
      `#{cmd}`
      
      path_num += 1
    end

    # GZIP
    cmd = niceify "gzip -f #{static_tar_path}"
    puts "\nGzip: #{cmd}" if @verbose
    `#{cmd}`

  end
  
  def backup_static
    dump_static
    # establish_ftp_connection
    file = final_static_dump_path()
    puts "\nBacking up Static files to FTP server: #{file}\n" if @verbose
    ftp file
    # @ftp.put file
  end
  
  def cleanup
    count = @fu_conf[:keep_backups].to_i
    # backups = Dir.glob("#{dump_base_path}/*.{sql}")
    backups = Dir.glob("#{dump_base_path}/*.*").collect {|f| 
      File.basename(f, File.extname(f)).split("_")[0,3].join("_")
    }.uniq.sort

    if count >= backups.length
      puts "[#{Time.now}] No old backups to cleanup: count: #{count}: backups: #{backups.length}"
    else
      puts "[#{Time.now}] Keeping #{count} of #{backups.length} backups"
    
      files_to_remove = []
      # files_to_remove = backups - backups.last(count)
      backups_to_remove = backups - backups.last(count)
    
      # files_to_remove = files_to_remove.concat(Dir.glob("#{dump_base_path}/*.{gz}")[0, files_to_remove.length]) unless @fu_conf[:disable_tar_gzip]
      files_to_remove =  backups_to_remove.collect {|backup| Dir.glob("#{dump_base_path}/#{backup}*.*")}.flatten    
      
      files_to_remove.each do |f|
        File.delete(f)
        puts "[#{Time.now}] Deleted #{f}" 
      end
    
    end
  end
  
  private
  
  def ftp(localfile, remotefile = File.basename(localfile))
    system "
    ftp -n -v #{@fu_conf[:ftp_server]} << EOT
    user #{@fu_conf[:username]} #{@fu_conf[:password]}
    cd #{@fu_conf[:remote_path]}
    prompt
    binary
    put #{localfile} #{remotefile}
    bye
    EOT
    "
  end
  
  def establish_ftp_connection
    unless @ftp && !@ftp.closed?
      @ftp = Net::FTP.new(@fu_conf[:ftp_server])
      begin
        @ftp.login(@fu_conf[:username], @fu_conf[:password])       
        @ftp.chdir @fu_conf[:remote_path]
      rescue Net::FTPPermError => e
        raise FtpConnectError, "\nERROR: Connection to FTP server failed."
      end
    end
  end
  
  def check_conf
    if @fu_conf[:app_name] == 'replace_me'
      raise BackupFuConfigError, 'Application name (app_name) key not set in config/backup_fu.yml.'
    # elsif @fu_conf[:s3_bucket] == 'some-s3-bucket'
    #   raise BackupFuConfigError, 'S3 bucket (s3_bucket) not set in config/backup_fu.yml.  This bucket must be created using an external S3 tool like S3 Browser for OS X, or JetS3t (Java-based, cross-platform).'
    # else
    #   # Check for access keys set as environment variables:
    #   if ENV.keys.include?('AMAZON_ACCESS_KEY_ID') && ENV.keys.include?('AMAZON_SECRET_ACCESS_KEY')
    #     @fu_conf[:aws_access_key_id] = ENV['AMAZON_ACCESS_KEY_ID']
    #     @fu_conf[:aws_secret_access_key] = ENV['AMAZON_SECRET_ACCESS_KEY']
    #   elsif @fu_conf[:aws_access_key_id].include?('--replace me') || @fu_conf[:aws_secret_access_key].include?('--replace me')
    #     raise BackupFuConfigError, 'AWS Access Key Id or AWS Secret Key not set in config/backup_fu.yml.'
    #   end
    end
  end
  
  def dump_path
    dump = {:postgresql => 'pg_dump',:mysql => 'mysqldump'}
    # Note: the 'mysqldump_path' config option is DEPRECATED but keeping this in for legacy config file support
    @fu_conf[:mysqldump_path] || @fu_conf[:dump_path] || dump[@db_conf[:adapter].intern]
  end
  
  def dump_base_path
    @fu_conf[:dump_base_path] || File.join(RAILS_ROOT, 'tmp', 'backup')
  end
  
  def db_filename
    "#{@fu_conf[:app_name]}_#{ @timestamp }_db.sql"
  end
  
  def db_filename_tarred
    db_filename.gsub('.sql', '.tar')
  end
  
  def final_db_dump_path
    if @fu_conf[:disable_tar_gzip]
      filename = db_filename
    else
      filename = db_filename.gsub('.sql', '.tar.gz')
    end
    File.join(dump_base_path, filename)
  end
  
  def static_tar_path
    f = "#{@fu_conf[:app_name]}_#{ @timestamp }_static.tar"
    File.join(dump_base_path, f)
  end
  
  def final_static_dump_path
    f = "#{@fu_conf[:app_name]}_#{ @timestamp }_static.tar.gz"
    File.join(dump_base_path, f)
  end
  
  def create_dirs
    ensure_directory_exists(dump_base_path)
  end
  
  def ensure_directory_exists(dir)
    FileUtils.mkdir_p(dir) unless File.exist?(dir)
  end
  
  def niceify(cmd)
    if @fu_conf[:enable_nice]
      "nice -n -#{@fu_conf[:nice_level]} #{cmd}"
    else
      cmd
    end
  end

  def datetime_formatted
    Time.now.strftime("%Y-%m-%d") + "_#{ Time.now.tv_sec }"
  end
  
end
