require 'jira_tool/version'
require 'logger'
require 'io/console'
require 'jira-ruby'
require 'git'
require 'active_support/core_ext/string/filters'
require 'active_support/time'
require 'redis'
require 'pry'
require 'jira_tool/null_git'
require 'jira_tool/null_redis'
require 'jira_tool/errors'

# https://github.com/sumoheavy/jira-ruby

module JiraTool
  class Client
    DEFAULT_CACHE_TIME = 14_400 # seconds to cache issues
    DEFAULT_IGNORE_BRANCHES = %w[master develop].freeze

    attr_reader :client, :default_project_key, :rapidview_id, :jira_site, :cache_time, :ignore_branches

    def initialize(**options)
      jira_options = {
        username: ENV['JIRA_USER'],
        password: ENV['JIRA_PASSWORD'],
        site: ENV['JIRA_SITE'],
        context_path: ENV['JIRA_CONTEXT_PATH'] || '',
        auth_type: :basic
      }.merge(options)

      @jira_site = ENV['JIRA_SITE']
      raise Errors::ConfigError, 'JIRA_SITE env var required!' and exit if jira_site.blank?

      @default_project_key = ENV['JIRA_DEFAULT_PROJECT_KEY']
      raise Errors::ConfigError, 'JIRA_DEFAULT_PROJECT_KEY env var required!' and exit if default_project_key.blank?

      @rapidview_id = ENV['JIRA_RAPIDVIEW_ID']
      raise Errors::ConfigError, 'JIRA_RAPIDVIEW_ID env var required!' and exit if rapidview_id.blank?

      # Optional environment:
      @cache_time = ENV['JIRA_CACHE_TIME'].to_i.nonzero? || DEFAULT_CACHE_TIME
      @ignore_branches = ENV['JIRA_IGNORE_BRANCHES']&.split(',')&.map(&:strip) || DEFAULT_IGNORE_BRANCHES

      @client = ::JIRA::Client.new(jira_options)
    end

    def git
      @git ||= begin
                 Git.open(Dir.pwd, log: Logger.new(nil))
               rescue ArgumentError
                 NullGit.new
               end
    end

    def project(key = default_project_key)
      @project[key] ||= client.Project.find(key)
    end

    def me
      client.options[:username]
    end

    STATUSES = %w[
      In-Progress
      Development
      Ready
      Backlog
    ].freeze

    def current_issue_key
      @current_issue_key ||= git.current_branch.split('/').first
      ignore_branches.include?(@current_issue_key) ? nil : @current_issue_key
    end

    def current_issue
      find_issue(current_issue_key)
    end

    def resolve_key(key)
      return nil if key.blank?

      if key.start_with?(/[A-Za-z]/)
        key.upcase.to_s
      else
        "#{default_project_key}-#{key}".upcase
      end
    end

    def find_issue(key)
      key = resolve_key(key) || current_issue_key
      issue = client.Issue.find(key)
      issue_to_magic_struct(issue)
    rescue JIRA::HTTPError => e
      abort("Issue #{key} not found.".colorize(color: :black, background: :red))
    end

    def url_for(issue_key)
      "#{jira_site}browse/#{issue_key}"
    end

    def board_url
      "#{jira_site}secure/RapidBoard.jspa?rapidView=#{rapidview_id}&projectKey=#{default_project_key}"
    end

    def redis
      @redis ||= begin
                   redis = Redis.new
                   redis.info
                   redis
                 rescue Redis::CannotConnectError
                   NullRedis.new
                 end
    end

    def current_sprint
      @current_sprint ||= begin
        key = "jira_tool.current_sprint.#{Date.current}"
        sprint = redis.get(key)
        if sprint.nil?
          sprint = client.Board.find(rapidview_id).sprints.find { |s| s.state == 'active' }
          delete_cache 'current_sprint'
          return nil if sprint.nil?

          sprint = sprint.to_json
          redis.set(key, sprint)
        end
        MagicStruct.new(sprint)
      end
    end

    def next_sprint
      @next_sprint ||= begin
        key = "jira_tool.next_sprint.#{Date.current}"
        sprint = redis.get(key)
        if sprint.nil?
          possible_sprints = client.Board.find(rapidview_id).sprints.filter { |s| s.state == 'future' }.sort_by(&:name)
          sprint = possible_sprints[0]
          delete_cache 'next_sprint'
          return nil if sprint.nil?

          sprint = sprint.to_json
          redis.set(key, sprint)
        end
        MagicStruct.new(sprint)
      end
    end

    def hide_key(key)
      hidden_keys << key.upcase unless hidden_keys.include?(key.upcase)
      redis.set('jira_tool.hidden_keys', hidden_keys.to_json)
      hidden_keys
    end

    def show_key(key)
      hidden_keys.delete(key.upcase) if hidden_keys.include?(key.upcase)
      redis.set('jira_tool.hidden_keys', hidden_keys.to_json)
      hidden_keys
    end

    def clear_hidden
      redis.set('jira_tool.hidden_keys', '[]')
      @hidden_keys = []
    end

    def hidden_keys
      @hidden_keys ||= JSON.parse(redis.get('jira_tool.hidden_keys') || '[]')
    end

    def delete_cache(key)
      redis.keys("jira_tool.#{key}.*").each do |del_key|
        redis.unlink del_key
      end
    end

    def issue_to_magic_struct(issue)
      issue_struct = MagicStruct.new(issue.fields)
      issue_struct.subtasks = issue.subtasks.map { |s| MagicStruct.new(s) }
      issue_struct.key = issue.key
      issue_struct.id = issue.id
      issue_struct.lastViewed = issue_struct.lastViewed&.to_datetime
      issue_struct.created = issue_struct.created&.to_datetime
      issue_struct.updated = issue_struct.updated&.to_datetime
      issue_struct
    end

    def issues(refresh: false, sprint: current_sprint)
      @issues ||= begin
        # Parameterized queries would be nice, but JIRA::Resource::Issue.jql runs CGI.escape anyway:

        key = "jira_tool.issues.#{sprint.id}.#{Time.now.to_i / cache_time}"
        issues = redis.get(key)
        if refresh || issues.nil?
          issues = client.Issue.jql(<<-JQL)
            sprint = #{sprint.id}
            AND
            status in ('#{STATUSES.join("', '")}')
            AND
            issuetype not in subtaskIssueTypes()
            ORDER BY Rank
          JQL

          issues.map! { |i| issue_to_magic_struct(i) }

          # issues.sort_by! { |issue| STATUSES.index(issue.status.name) }

          delete_cache "issues.#{sprint.id}"
          redis.set(key, issues.map(&:to_h).to_json)
          puts 'REFRESHED ISSUES!'.colorize(:green)
        else
          puts 'CACHED ISSUES: Run `jira r` to refresh the cache.'.colorize(:blue)
          issues = JSON.parse(issues).map { |i| MagicStruct.new(i) }
        end

        issues
      end
    end
  end
end
