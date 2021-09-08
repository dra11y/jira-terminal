require 'getoptlong'

module JiraTool
  class CLI
    attr_reader :issue, :issues

    def initialize
      parse_command!
    end

    %i[board refresh subtasks checkout delbranch current backlog todo pluck list all none open show hide pr].each do |name|
      define_method("#{name}?") do
        instance_variable_get("@#{name}")
      end
    end

    def issue?
      @issue.present?
    end

    private

    # Right now this is just for help text... we may
    # be able to refactor to make DRY...
    COMMANDS = [
      {
        commands: %w[h help -h --help],
        arg: nil,
        help: 'show help'
      },
      {
        commands: [],
        arg: '[PROJECT-]ISSUE#',
        help: <<~HELP_TEXT
          show details of the given issue
          Ex:   `jira 1234` is equivalent to `jira PE-1234`
                if default project is set to `PE`
        HELP_TEXT
      },
      {
        commands: %w[a all],
        arg: nil,
        help: 'show entire team\'s issues on current RapidView board'
      },
      {
        commands: %w[todo todos],
        arg: nil,
        help: 'show unassigned issues on current RapidView board'
      },
      {
        commands: %w[b backlog],
        arg: nil,
        help: 'show backlog issues for upcoming sprint'
      },
      {
        commands: %w[l list],
        arg: '[ISSUE] [ISSUE] ...',
        help: 'list/summarize the specified or current board issues'
      },
      {
        commands: %w[r refresh],
        arg: nil,
        help: 're-download latest issues from RapidView board into Redis'
      },
      {
        commands: %w[c current],
        arg: nil,
        help: <<~HELP_TEXT
          view current issue details based on checked-out branch
          Ex:   `git checkout -b PE-1234/test-issue`
                `jira c` is then equivalent to `jira PE-1234`
        HELP_TEXT
      },
      {
        commands: %w[o open],
        arg: '[ISSUE]',
        help: <<~HELP_TEXT
          open the current or specified issue in your default browser
        HELP_TEXT
      },
      {
        commands: %w[hide],
        arg: 'ISSUE',
        help: <<~HELP_TEXT
          mark specified issue as hidden in local Redis cache
          (it won't be displayed unless queried directly,
            and WILL NOT affect any data in Jira)
        HELP_TEXT
      },
      {
        commands: %w[show],
        arg: 'ISSUE | ALL',
        help: <<~HELP_TEXT
          un-hide the specified issue (or all issues) in local Redis
        HELP_TEXT
      },
      {
        commands: %w[subtasks sub t],
        arg: 'ISSUE',
        help: <<~HELP_TEXT
          include a colorized list of subtasks in the issue details
        HELP_TEXT
      },
      {
        commands: %w[pr pull],
        arg: 'ISSUE',
        help: <<~HELP_TEXT
          print a pull request template for ISSUE to the terminal;
          (uses `PR_TEMPLATE.md` as a template)
        HELP_TEXT
      },
      {
        commands: %w[co checkout],
        arg: 'ISSUE',
        help: <<~HELP_TEXT
          Perform a `git checkout -b`, automatically naming the branch
          based on the parameterized (kebab-case) issue summary
        HELP_TEXT
      },
      {
        commands: %w[delbranch],
        arg: '[ISSUE]',
        help: <<~HELP_TEXT
          Delete the local issue branch based on the automatic naming
          of `jira checkout ISSUE` (defaults to current branch)
        HELP_TEXT
      },
      {
        commands: ['board', 'o board'],
        arg: nil,
        help: <<~HELP_TEXT
          Open your team's RapidView (Scrum) Board in your browser.
        HELP_TEXT
      }
    ].freeze

    # Yeah, this is not DRY... we can improve...
    def parse_command!
      case ARGV.first
      when nil
        @none = true
      when 'v', 'version', '--version', '-v'
        print_version_and_exit
      when 'help', 'h', '--help', '-h'
        print_help_and_exit
      when 'board'
        @board = true
      when 'refresh', 'r'
        @refresh = true
      when 'checkout', 'co'
        @checkout = true
        @issue = ARGV[1]
      when 'delbranch'
        @delbranch = true
        @issue = ARGV[1]
      when 'current', 'c'
        @current = true
      when 'backlog', 'b'
        @backlog = true
      when 'all', 'a'
        @all = true
      when 'todo', 'todos'
        @todo = true
      when 'pluck'
        @pluck = true
      when 'list', 'l'
        @list = true
        @issues = ARGV[1...]
      when 'open', 'o'
        @issue = ARGV[1]
        if @issue == 'board'
          @board = true
        else
          @open = true
        end
      when 'show'
        @show = true
        @issue = ARGV[1]
      when 'hide'
        @hide = true
        @issue = ARGV[1]
      when 'subtasks', 'subs', 'sub', 'tasks', 'st', 't'
        @subtasks = true
        @issue = ARGV[1]
      when 'pr', 'pull'
        @pr = true
        @issue = ARGV[1]
      else # assume it's an issue
        @issue = ARGV.first
      end
    end

    def print_help_and_exit
      print_version
      help_text = "Usage: jira [COMMAND]   show your issues on the current RapidView board\n\n"
      COMMANDS.each do |command|
        help_text << (command[:commands].join(', ') + '  ' + command[:arg].to_s).strip.ljust(24)
        help_text << command[:help].split("\n").join("\n#{' ' * 24}") << "\n\n"
      end
      puts help_text
      print_environment_warning
      exit 0
    end

    def print_version_and_exit
      print_version
      exit 0
    end

    def print_version
      puts "JiraTool v#{JiraTool::VERSION}"
    end

    REQUIRED_ENVS = %w[JIRA_USER JIRA_PASSWORD JIRA_SITE JIRA_DEFAULT_PROJECT_KEY JIRA_RAPIDVIEW_ID].freeze

    def print_environment_warning
      return if REQUIRED_ENVS.map { |e| ENV[e].present? }.all?

      print 'WARNING: The following environment variables are required'.colorize(color: :red)
      puts ' (green = OK):'.colorize(color: :green)
      envs_warning = REQUIRED_ENVS.map do |e|
        color = ENV[e].present? ? :green : :red
        e.colorize(color: color)
      end.join(', ')
      puts envs_warning
    end
  end
end
