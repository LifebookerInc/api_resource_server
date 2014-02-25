# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'api_resource_server/version'

Gem::Specification.new do |spec|
  spec.name          = "api_resource_server"
  spec.version       = ApiResourceServer::VERSION
  spec.authors       = ["ams340"]
  spec.email         = ["aaron.streiter@lifebooker.com"]
  spec.description   = %q{TODO: Write a gem description}
  spec.summary       = %q{TODO: Write a gem summary}
  spec.homepage      = ""
  spec.license       = "MIT"

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_dependency "autoscope"
  spec.add_dependency "activesupport"

  spec.add_development_dependency "activerecord"
  spec.add_development_dependency "bundler", "~> 1.3"
  spec.add_development_dependency "guard-bundler"
  spec.add_development_dependency "guard-rspec"
  spec.add_development_dependency "rake"

end
