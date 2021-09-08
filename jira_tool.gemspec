require_relative 'lib/jira_tool/version'

Gem::Specification.new do |gem|
  gem.name          = 'jira_tool'
  gem.version       = JiraTool::VERSION
  gem.authors       = ['Tom Grushka']
  gem.email         = ['tom@dra11y.com']

  gem.summary       = 'Command-line tool to interact with Jira and Git.'
  gem.description   = 'Command-line tool to interact with Jira and Git.'
  gem.homepage      = 'https://github.com/dra11y/jira-terminal.git'
  gem.required_ruby_version = Gem::Requirement.new('>= 2.3.0')

  gem.metadata['allowed_push_host'] = "TODO: Set to 'http://mygemserver.com'"

  gem.metadata['homepage_uri'] = gem.homepage
  gem.metadata['source_code_uri'] = gem.homepage
  gem.metadata['changelog_uri'] = gem.homepage

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gem.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  gem.bindir = 'bin'
  gem.executables   = gem.files.grep(%r{^bin/}) { |f| File.basename(f) }
  gem.require_paths = ['lib']
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})

  gem.add_dependency 'activesupport', '~> 6.0' # using some Rails time helpers
  gem.add_dependency 'colorize', '~> 0.8' # colors output to terminal
  gem.add_dependency 'dotiw', '~> 5.1' # distance of time in words
  gem.add_dependency 'git', '~> 1.7' # Git API for Ruby
  gem.add_dependency 'jira-ruby', '~> 2.1' # JIRA REST API
  gem.add_dependency 'launchy', '~> 2.5' # opens default browser given URL
  gem.add_dependency 'redis', '~> 4.2' # local caching of JIRA REST data

  gem.add_development_dependency 'pry'
  gem.add_development_dependency 'rake', '~> 12.0'
  gem.add_development_dependency 'rspec', '~> 3.0'
end
