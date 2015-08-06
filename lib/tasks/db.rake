namespace :db do
  desc 'Fetch Heroku pg dump and restore it to local DB'
  task :get_pgdump, [:pg_dump_id] => :environment do |t, args|
    #
    # Example uses:
    #   rake db:get_pgdump[b030]
    #   rake db:get_pgdump[b030] APP=my-heroku-app (default is nothing)
    #   rake db:get_pgdump[b030] DB=development (default)
    #

    # Validate pg_dump_id (required arg)
    if args[:pg_dump_id].nil?
      abort('A postgres dump ID is required, e.g. b039')
    end

    # Validate DB_ENV optional arg
    db_env = 'development'
    if ENV['DB'].nil?
      puts 'No DB provided, proceeding with default of development'
    else
      if %w(development test production).include?(ENV['DB'])
        db_env = ENV['DB']
      else
        abort('Not a valid db env: %s' % ENV['DB'])
      end
    end

    puts 'Downloading PG dump...'
    cmd_get_pgdump = 'heroku pg:backups public-url %s' % args[:pg_dump_id]

    if ENV['APP'].nil?
      puts 'No APP provided, will proceed w/o specifying a Heroku app...'
    else
      puts 'Using app %s' % ENV['APP']
      cmd_get_pgdump << ' --app %s' % ENV['APP']
    end

    pg_dump_url = nil
    Bundler.with_clean_env { pg_dump_url = `#{cmd_get_pgdump}` }

    if pg_dump_url.nil? or pg_dump_url == ''
      abort('Download failed, something went wrong when executing pg:backups')
    end

    if !pg_dump_url.start_with?('http')
      abort('Download failed, unexpected output from pg:backups!')
    end

    pgdump_dst = File.join(ENV['HOME'], 'Downloads', 'heroku_pg.dump')
    curl_cmd = 'curl "%s" > %s' % [pg_dump_url.strip, pgdump_dst]
    `#{curl_cmd}`

    if !File.exist?(pgdump_dst)
      abort('Download failed, no file: %s' % pgdump_dst)
    end

    puts 'Setting up fresh DB instance'
    Rake::Task['db:drop'].execute
    Rake::Task['db:create'].execute
    Rake::Task['db:migrate'].execute
    Rake::Task['db:setup'].execute

    puts 'Restoring pg dump to local DB'
    db_name = YAML.load(File.read(File.expand_path(Rails.root + 'config/database.yml')))[db_env]['database']
    if db_name.nil?
      abort('Failed to find database name in config/database.yml')
    end
    puts 'Using database: %s' % db_name
    pg_restore_cmd = 'pg_restore --verbose --clean --no-acl --no-owner -h localhost -d %s %s' % [db_name, pgdump_dst]
    `#{pg_restore_cmd}`
    puts 'Done.'
  end
end
