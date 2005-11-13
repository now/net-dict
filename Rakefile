# contents:
#
# Copyright © 2005 Nikolai Weibull <nikolai@bitwi.se>

require 'rubygems'
require 'rake'
require 'rake/gempackagetask'
require 'rake/rdoctask'
require 'rake/testtask'

PackageName = 'net-dict'
PackageVersion = IO.read('doc/README') =~ /^(\d+(\.\d+){2})\n~+$/ && $~[1]
raise 'no version information found in doc/README' unless PackageVersion
PackageFiles = FileList['{doc,lib}/**/*']

desc 'Default task'
task :default => [:test]

desc 'Extract embedded documentation and build HTML documentation'
task :doc => [:rdoc]
task :rdoc => FileList['lib/**/*.rb']

desc 'Clean up by removing all generated files, e.g., documentation'
task :clean => [:clobber_rdoc]

Rake::TestTask.new do |t|
  t.test_files = []
  t.verbose = true
end

RDocDir = 'api'

Rake::RDocTask.new do |rdoc|
  rdoc.rdoc_dir = RDocDir
  rdoc.title = 'Net::DICT'
  rdoc.options = ['--charset UTF-8']
  rdoc.rdoc_files.include('lib/**/*.rb')
end

spec = Gem::Specification.new do |s|
  s.name = PackageName
  s.version = PackageVersion
  s.summary = "Net::DICT implements the client-side of the Dictionary Server Protocol (DICT)."
  s.files = PackageFiles.to_a
  s.require_path = 'lib'
  s.has_rdoc = true
  s.author = 'Nikolai Weibull'
  s.email = 'nikolai@bitwi.se'
  s.homepage = 'http://git.bitwi.se'
end

Rake::GemPackageTask.new(spec) do |package|
  package.need_tar_bz2 = true
end
