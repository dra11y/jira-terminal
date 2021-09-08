# Jira Terminal Client

## Improves Jira Accessibility (A11y)

## Installation

**For Ruby 2.6+**

Clone the repo:

```
git clone git@github.com:dra11y/jira-terminal.git
```

Add the executable to your environment:

```
alias jira='BUNDLE_GEMFILE=~/jira_tool/Gemfile bundle exec jira'
```

Install gem dependencies:

```
cd ~/jira_tool
bundle install
```

Install Redis with default options (optional; required for show/hide issue functionality; caches issues for faster execution):

```
brew install redis
brew services start redis
```

## Setup

Set the following variables in your environment:

#### Required Environment Vars:

- `JIRA_USER` = your JIRA username
- `JIRA_PASSWORD` = your JIRA password
- `JIRA_SITE` = your JIRA site URL with trailing slash, i.e. https://jira.yoursite.com/
- `JIRA_DEFAULT_PROJECT_KEY` = your JIRA project ID
- `JIRA_RAPIDVIEW_ID` = the JIRA Board ID obtained from the URL: `https://jira.yoursite.com/secure/RapidBoard.jspa?rapidView=100&projectKey=SomeKey`

#### Optional Environment Vars:

- `JIRA_CONTEXT_PATH` = the context path in your JIRA installation (required only if your JIRA installation has a context path; usually blank; default = '')
- `JIRA_CACHE_TIME` = number of seconds to cache issues in Redis; defaults to `14_400` (4 hours)
- `JIRA_IGNORE_BRANCHES` = branches that will raise an error if the tool assumes they are issue branches when it queries for the current issue key, and should thus be ignored for this purpose; comma-separated list; defaults to `master,develop`.

#### Pull Request Template:

Copy `PR_TEMPLATE.example.md` to `PR_TEMPLATE.md` and customize to your corporate PR template. The following tokens are used:

- `<DESCRIPTION>` - inserts the issue summary and description;
- `<EPIC>` - inserts the epic number of the issue;
- `<ISSUES>` - inserts the issue and subtasks with keys, summaries, and web links to Jira.

You can then run `jira pr 1234` to generate the PR text and copy/paste it into Github. **This currently does not actually open a PR!**

## Usage

Run `jira` in your project's current working directory. It will not write to your project or to Jira in any way. However, it will read your current Git branch to determine the current issue you're working on (format: "ISSUE-KEY/ignored-text").

The current output of `jira help` is:

```
JiraTool v0.1.0
Usage: jira [COMMAND]   show your issues on the current RapidView board

h, help, -h, --help     show help

[PROJECT-]ISSUE#        show details of the given issue
                        Ex:   `jira 1234` is equivalent to `jira PE-1234`
                              if default project is set to `PE`

a, all                  show entire team's issues on current RapidView board

r, refresh              re-download latest issues from RapidView board into Redis

c, current              view current issue details based on checked-out branch
                        Ex:   `git checkout -b PE-1234/test-issue`
                              `jira c` is then equivalent to `jira PE-1234`

o, open  [ISSUE]        open the current or specified issue in your default browser

hide  ISSUE             mark specified issue as hidden in local Redis cache
                        (it won't be displayed unless queried directly,
                          and WILL NOT affect any data in Jira)

show  ISSUE | ALL       un-hide the specified issue (or all issues) in local Redis

subtasks, sub, t  ISSUE include a colorized list of subtasks in the issue details

pr, pull  ISSUE         print a pull request template for ISSUE to the terminal;
                        (uses `PR_TEMPLATE.md` as a template)

co, checkout  ISSUE     Perform a `git checkout -b`, automatically naming the branch
                        based on the parameterized (kebab-case) issue summary

delbranch  [ISSUE]      Delete the local issue branch based on the automatic naming
                        of `jira checkout ISSUE` (defaults to current branch)
```

## Development

**This section must be updated!**

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/dra11y/jira-terminal.
