	$LOAD_PATH.unshift(File.expand_path("../lib", __FILE__))
require "google-contacts-w-avatar/version"

Gem::Specification.new do |s|
  s.name        = "google-contacts-w-avatar"
  s.version     = GoogleContacts::VERSION
  s.platform    = Gem::Platform::RUBY
  s.authors     = ["Zachary Anker", "Maksim Koritskiy"]
  s.email       = ["zach.anker@gmail.com", "max@koritskiy.ru"]
  s.homepage    = "http://github.com/nightweb/google-contacts-w-avatar"
  s.summary     = "Google Contacts (v2 and v3) library with ClientLogin auth and manage avatars"
  s.description = "Helps manage both the importing and exporting of Google Contacts (v2 && v3) data"

  s.required_rubygems_version = ">= 1.3.6"

  s.add_runtime_dependency "nokogiri", "~>1.6.0"
  s.add_runtime_dependency "nori", "~>1.1.0"
  s.add_runtime_dependency 'gdata'
  s.add_runtime_dependency 'google-api-client', '~> 0.6.4'
  s.add_runtime_dependency 'mime-types', '~> 1.25'

  s.add_runtime_dependency "jruby-openssl", "~>0.7.0" if RUBY_PLATFORM == "java"

  s.add_development_dependency "rspec", "~>2.8.0"
  s.add_development_dependency "guard-rspec", "~>0.6.0"
  s.licenses = ['MIT', 'GPL-2']


  s.files        = Dir.glob("lib/**/*") + %w[GPL-LICENSE MIT-LICENSE README.rdoc CHANGELOG.md Rakefile]
  s.require_path = "lib"
end