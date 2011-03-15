class TestSuite
  attr_reader :name, :options, :config

  def initialize(name, options, config)
    @name    = name.gsub(/\s+/, '-')
    @run     = false
    @options = options
    @config  = config

    @test_cases = []
    @test_files = []

    Array(options[:tests] || 'tests').each do |root|
      if File.file? root then
        @test_files << root
      else
        @test_files += Dir[File.join(root, "**/*.rb")].select { |f| File.file?(f) }
      end
    end
    fail "no test files found..." if @test_files.empty?

    if options[:random]
      @random_seed = (options[:random] == true ? Time.now : options[:random]).to_i
      srand @random_seed
      @test_files = @test_files.sort_by { rand }
    else
      @test_files = @test_files.sort
    end
  end

  def run
    @run = true
    @start_time = Time.now

    initialize_logfiles

    summary = []

    initialize_logfiles

    Log.notify "Using random seed #{@random_seed}" if @random_seed
    @test_files.each do |test_file|
      Log.notify

      test_case = TestCase.new(config, options, test_file).run_test
      @test_cases << [test_file, test_case]

      status_color = case test_case.test_status
                     when :pass
                       Log::GREEN
                     when :fail
                       Log::RED
                     when :error
                       Log::YELLOW
                     end
      Log.notify "#{status_color}#{test_file} #{test_case.test_status}ed#{Log::NORMAL}"
    end

    summarize(options[:stdout]) unless options[:stdout_only]

    @test_cases
  end

  def run_and_exit_on_failure
    return if success?
    $org_stdout.puts "Failed while running the #{name} suite..."
    Log.error "Failed while running the #{name} suite..."
    exit 1
  end

  def success?
    fail "you have not run the tests yet" unless @run
    sum_failed == 0
  end
  def failed?
    !success?
  end

  private

  def sum_failed
    test_failed=0
    test_passed=0
    test_errored=0
    @test_cases.each do |test, test_case|
      case test_case.test_status
      when :pass then test_passed += 1
      when :fail then test_failed += 1
      when :error then test_errored += 1
      end
    end
    test_failed + test_errored
  end

  def summarize(to_stdout)
    fail "you have not run the tests yet" unless @run

    if to_stdout then
      Log.notify "\n\n"
    else
      sum_log = File.new(File.join(log_dir, "/#{name}-summary.txt"), "w")
      $stdout = sum_log     # switch to logfile for output
      $stderr = sum_log
    end

    Log.notify <<-HEREDOC
  Test Pass Started: #{@start_time}

  - Host Configuration Summary -
    HEREDOC

    TestConfig.dump(config)

    test_failed=0
    test_passed=0
    test_errored=0
    @test_cases.each do |test, test_case|
      case test_case.test_status
      when :pass then test_passed += 1
      when :fail then test_failed += 1
      when :error then test_errored += 1
      end
    end
    grouped_summary = @test_cases.group_by{|test,test_case| test_case.test_status }

    Log.notify <<-HEREDOC

  - Test Case Summary -
  Attempted: #{@test_cases.length}
     Passed: #{test_passed}
     Failed: #{test_failed}
    Errored: #{test_errored}

  - Specific Test Case Status -
  HEREDOC

    Log.notify "Failed Tests Cases:"
    (grouped_summary[:fail] || []).each {|test, test_case| print_test_failure(test, test_case)}

    Log.notify "Errored Tests Cases:"
    (grouped_summary[:error] || []).each {|test, test_case| print_test_failure(test, test_case)}

    sum_log.close unless to_stdout
  end

  def print_test_failure(test, test_case)
    Log.notify "  Test Case #{test} reported: #{test_case.exception.inspect}"
  end

  def log_path(name)
    @@log_dir ||= File.join("log", @start_time.strftime("%F_%T"))
    unless File.directory?(log_dir) then
      FileUtils.mkdir(log_dir)
      FileUtils.cp(options[:config],(File.join(log_dir,"config.yml")))

      latest = File.join("log", "latest")
      if File.symlink?(latest) then
        File.delete(latest)
        File.symlink(File.basename(log_dir), latest)
      end
    end

    File.join('log', 'latest', name)
  end

  # Setup log dir
  def initialize_logfiles
    return if options[:stdout_only]

    run_log = File.new(log_path("run-#{name}.log"), "w")

    if ! options[:quiet]
      run_log = Tee.new(run_log)
    end

    $stdout = run_log
    $stderr = run_log
  end
end
