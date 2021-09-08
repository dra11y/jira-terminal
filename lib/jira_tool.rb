require 'jira_tool/version'
require 'logger'
require 'io/console'
require 'jira-ruby'
require 'git'
require 'launchy'
require 'colorize'
require 'active_support/core_ext/string/filters'
require 'active_support/time'
require 'redis'
require 'pry'
require 'jira_tool/errors'
require 'jira_tool/magic_struct'
require 'jira_tool/client'
require 'jira_tool/cli'
require 'jira_tool/date_helper'
require 'jira_tool/enumerable'

# https://github.com/sumoheavy/jira-ruby

module JiraTool
  class Jira
    PR_TEMPLATE_FILE = File.expand_path('..', __dir__) + '/PR_TEMPLATE.md'.freeze

    def client
      @client ||= Client.new
    end

    def open_in_browser(key)
      issue_key = if key == 'board'
                    'board'
                  elsif key.present?
                    client.find_issue(key).key
                  else
                    client.current_issue_key
                  end
      issue_key ? browse_to(issue_key) : puts('No issue from current branch.'.colorize(:red))
    end

    def execute
      command = CLI.new
      if command.none?
        print_issues
      elsif command.board?
        open_in_browser 'board'
      elsif command.refresh?
        print_issues(refresh: true)
      elsif command.all?
        print_issues(all: true)
      elsif command.pluck?
        print_issues(unassigned: true, pluck: true)
      elsif command.todo?
        print_issues(unassigned: true)
      elsif command.backlog?
        print_issues(unassigned: true, backlog: true)
      elsif command.list?
        list_issues(command.issues)
      elsif command.open?
        open_in_browser command.issue
      elsif command.checkout?
        checkout command.issue
      elsif command.delbranch?
        delbranch command.issue
      elsif command.current?
        print_issue client.current_issue, truncate: false
      elsif command.subtasks?
        print_issue client.find_issue(command.issue), subtasks: true
      elsif command.show?
        show_issue command.issue
      elsif command.hide?
        hide_issue command.issue
      elsif command.pr?
        pr_template command.issue
      else # issue key given?
        print_issue client.find_issue(command.issue), assignee: true, truncate: false
      end
    end

    def issue_branch(issue_key)
      @issue_branch ||= {}
      @issue_branch[:issue_key] ||= begin
        issue = client.find_issue(issue_key)
        desc = issue.summary.truncate_words(10, omission: '').parameterize
        "#{issue.key}/#{desc}"
      end
    end

    def exit_if_git_dirty!
      return if `git status -s | wc -l`.strip == '0'

      puts 'Cannot checkout -- dirty working tree!'.colorize(:red)
      exit 1
    end

    def checkout_develop!
      `git checkout develop` if `git branch --show-current`.strip != 'develop'
      puts 'Pulling latest develop branch...'
      `git pull`
    end

    def delbranch(key)
      exit_if_git_dirty!
      issue_key = key.present? ? client.find_issue(key).key : client.current_issue_key
      branch_name = issue_branch(issue_key)
      print "DELETE LOCAL BRANCH #{branch_name}: ARE YOU SURE? ".colorize(color: :red)
      confirm = STDIN.gets.chomp.downcase
      unless %w[y yes].include? confirm
        puts 'Cancelled.'
        return
      end

      checkout_develop!
      `git branch -D #{branch_name}`
      puts "\nDELETED LOCAL BRANCH: #{branch_name}".colorize(color: :red)
    end

    def checkout(issue_key)
      exit_if_git_dirty!
      checkout_develop!
      `git checkout -b #{issue_branch(issue_key)}`
    end

    def pr_template(issue_key)
      found_template = true
      template = begin
        File.read(PR_TEMPLATE_FILE)
                 rescue Errno::ENOENT
                   found_template = false
                   "<DESCRIPTION>\n\nEPIC: <EPIC>\n\nISSUES: <ISSUES>"
      end

      issue = client.find_issue(issue_key)
      template.gsub!('<SUMMARY>', pr_issue_link(issue))
      template.gsub!('<DESCRIPTION>', pr_issue_description(issue))
      issue_and_subtasks = pr_issue_link(issue)
      # if issue.subtasks
      #   issue_and_subtasks += "\n\tSubtasks:\n\t" + issue.subtasks.map { |st| pr_issue_link(st) }.join("\n\t")
      # end
      template.gsub!('<ISSUES>', issue_and_subtasks)
      template.gsub!('<EPIC>', pr_epic_link(issue) || 'No epic.')
      puts template
      return if found_template

      puts "\nWARNING! Template file #{PR_TEMPLATE_FILE} not found. Please copy #{PR_TEMPLATE_FILE.gsub('md', 'example.md')} to #{PR_TEMPLATE_FILE} and customize.".colorize(color: :red)
    end

    def pr_epic_link(issue)
      epic = client.find_issue(issue.customfield_10101)
      "[#{issue.customfield_10101}](#{client.url_for(epic.key)}) - #{epic.fields&.summary || epic.summary}"
    end

    def pr_issue_link(issue)
      "[#{issue.key}](#{client.url_for(issue.key)}) - #{issue.fields&.summary || issue.summary}"
    end

    def pr_issue_description(issue)
      "#{pr_issue_link(issue)}\n\n#{issue.description}"
    end

    def browse_to(issue_key)
      if issue_key == 'board'
        Launchy.open(client.board_url)
      else
        Launchy.open(client.url_for(issue_key))
      end
    end

    def show_issue(key)
      puts('Please provide an issue to show, or ALL.') || return if key.blank?

      if key.upcase == 'ALL'
        client.clear_hidden
        puts 'Cleared all hidden issues.'
        return
      end

      key = client.resolve_key(key)
      puts('Not hidden.') || return unless client.hidden_keys.include?(key)

      result = client.show_key(key)
      puts "#{key} removed from hidden issues. Now hiding: #{result}"
    end

    def hide_issue(key)
      puts('Please provide an issue to hide.') || return if key.blank?

      key = client.resolve_key(key)
      puts('Already hidden.') || return if client.hidden_keys.include?(key)

      result = client.hide_key(key)
      puts "#{key} added to hidden issues. Now hiding: #{result}"
    end

    def list_issues(issue_keys)
      issue_keys.each do |issue_key|
        list_issue issue_key
      end
    end

    def list_issue(issue_key)
      issue = client.find_issue(issue_key)
      print issue_key
      # new assigned issue key?
      print " -> #{issue.key}" unless issue.key == issue_key
      puts " - #{issue.summary}"
    end

    def print_issue(issue, assignee: false, truncate: 25, comments: true, subtasks: false)
      print_title(issue, assignee: assignee)

      print_parent(issue)

      print_timestamps(issue)

      print_acceptance_criteria(issue, truncate: truncate)

      print_body(issue, truncate: truncate)

      print_comments(issue, comments: comments)

      print_subtasks(issue, subtasks: subtasks)
    end

    def print_parent(issue)
      return if issue.parent.blank?

      puts "---> SUBTASK of #{issue.parent.key}: #{issue.parent.fields.summary}\n"
    end

    def print_acceptance_criteria(issue, truncate: 25)
      criteria = issue.customfield_10602
      return if criteria.blank?

      criteria = criteria.truncate_words(truncate) if truncate
      criteria = "#{'-' * 7} Acceptance Criteria:\n#{criteria}"
      puts criteria.colorize(color: :green)
    end

    def print_title(issue, assignee: false)
      color = background = :default

      if client.current_issue_key == issue.key
        color = :black
        background = :green
      end

      title = "#{issue.key}  [#{issue.status&.name}]  #{issue.customfield_10101.presence}  "
      title += issue.summary
      title += "  (#{issue.customfield_10106.to_i} pts)"
      title = "#{issue.assignee&.displayName || 'Unassigned'}  <-  #{title}" if assignee
      puts title.colorize(color: color, background: background, mode: :bold)
    end

    def print_body(issue, truncate: 25)
      description = issue.description.to_s
      description = description.truncate_words(truncate) if truncate
      puts
      puts colorize_markdown(description)
    end

    def colorize_markdown(md)
      md.gsub!(/(h\d\..*)/, '\1'.colorize(color: :yellow))

      links_re = %r{https?:\/\/[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9()]{1,6}\b([-a-zA-Z0-9()@:%_\+.~#?&//=]*)}x
      md.gsub!(links_re, '\0'.colorize(color: :blue))

      md.gsub!(/\*.*\*/, '\0'.colorize(mode: :bold))
      md
    end

    def print_timestamps(issue)
      puts "Created #{DateHelper.ago(issue.created)}, Updated #{DateHelper.ago(issue.updated)}".colorize(:blue)
    end

    def print_comments(issue, comments: true)
      return if issue.comment.blank? || issue.comment.comments.blank?

      puts "\n#{'-' * 7} #{issue.comment.comments.size} Comments\n".colorize(mode: :bold)
      return unless comments

      puts "#{'Created'.ljust(14)}#{'Author'.ljust(15)}Comment".colorize(color: :green, mode: :bold)
      issue.comment.comments.each do |comment|
        print DateHelper.ago(comment.created).ljust(14).colorize(color: :green)
        print comment.author.displayName.ljust(15).colorize(color: :green)
        puts comment.body
      end
    end

    def print_subtasks(issue, subtasks: false)
      return unless issue.subtasks&.count&.positive?

      counts = issue.subtasks.count_by { |s| s.fields.status.name }
      print "\n#{'-' * 7} #{issue.subtasks.count} Subtasks:".colorize(mode: :bold)
      counts.each do |status, count|
        print "  #{count} #{status || 'No status'}".colorize(status_color(status))
      end
      puts

      return unless subtasks

      puts "\n#{'Subtask'.ljust(10)}#{'Status'.ljust(13)}#{'Priority'.ljust(10)}Summary".colorize(mode: :bold)
      issue.subtasks.each do |subtask|
        color = status_color(subtask.fields.status.name)
        priority = subtask.fields.priority&.name || 'Unset'
        row = subtask.fields.assignee.to_s
        row += "#{subtask.key.ljust(10)}#{subtask.fields.status.name.ljust(13)}".colorize(color)
        row += priority.ljust(8).colorize(priority_color(priority)) + '  '
        row += subtask.fields.summary.truncate(40).to_s.colorize(color)
        puts row
      end
    end

    def priority_color(priority)
      case priority
      when 'Highest' then { color: :black, background: :red }
      when 'Medium' then { color: :black, background: :yellow }
      when 'Lowest' then { color: :black, background: :blue }
      else { color: :red }
      end.merge(mode: :bold)
    end

    def status_color(status)
      case status
      when 'In-Progress' then :yellow
      when 'Done' then :green
      else :red
      end
    end

    def term_width
      @term_width ||= IO.console.winsize[1]
    end

    def sprint_info(sprint)
      weekdays = DateHelper.weekdays_until sprint.endDate&.to_date
      "#{sprint.name} (ends #{weekdays} weekdays from now on #{sprint.endDate&.to_date})"
    end

    def print_issues(refresh: false, all: false, unassigned: false, pluck: false, backlog: false)
      sprint = backlog ? client.next_sprint : client.current_sprint
      puts sprint_info(sprint)

      issues = client.issues(refresh: refresh, sprint: sprint)

      if all || issues.blank?
        puts 'ALL BOARD ISSUES'
        puts 'No issues currently on board.' if issues.count.zero?
      elsif unassigned
        issues.filter! { |i| i.assignee.blank? }
        puts(pluck ? 'NEXT UNASSIGNED BOARD ISSUE' : 'UNASSIGNED BOARD ISSUES')
        puts 'No unassigned issues currently on board.' if issues.count.zero?
      else
        issues.filter! { |i| i.assignee&.name == client.me }
        puts 'No issues currently assigned to you.' if issues.count.zero?
      end

      issues.each do |issue|
        next if client.hidden_keys.include?(issue.key)

        truncate = pluck ? nil : 25
        print_issue issue, truncate: truncate, assignee: (all | unassigned)
        break if pluck

        puts '-' * term_width
      end

      unless client.hidden_keys.blank?
        puts "HIDDEN: #{client.hidden_keys} (use `jira show ISSUE | ALL` to unhide)".colorize(:red)
      end

      # issue.summary
      # issue.description
      # sprint info? issue.customfield_10105
      # epic branch: issue.customfield_10101
      # team: issue.customfield_10400['value']
      # story points: issue.customfield_10106
      # acceptance criteria: issue.customfield_10602
      # issue.issuetype.name = Story
      # issue.issuelinks.map { |link| link.outwardIssue.key }
      # issue.subtasks -> dict i.e. issue.subtasks.map { |s| s['fields']['key'] } # summary, etc
    end
  end
end
