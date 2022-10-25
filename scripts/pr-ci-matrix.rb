#!/usr/bin/env ruby
# A script to generate the .jenkins.yml file for the CI pull request job
XCODE_VERSIONS = %w(13.4.1 14.0.1 14.1 14.2)

all = ->(v) { true }
latest_only = ->(v) { v == XCODE_VERSIONS.last }
oldest_and_latest = ->(v) { v == XCODE_VERSIONS.first or v == XCODE_VERSIONS.last }

def minimum_version(major)
  ->(v) { v.split('.').first.to_i >= major }
end

targets = {
  'docs' => latest_only,
  'swiftlint' => latest_only,

  'osx' => all,
  'osx-encryption' => latest_only,
  'osx-object-server' => oldest_and_latest,

  'swiftpm' => oldest_and_latest,
  'swiftpm-debug' => all,
  'swiftpm-address' => latest_only,
  'swiftpm-thread' => latest_only,
  'swiftpm-ios' => all,

  'ios-static' => oldest_and_latest,
  'ios-dynamic' => oldest_and_latest,
  'watchos' => oldest_and_latest,
  'tvos' => oldest_and_latest,

  'osx-swift' => all,
  'ios-swift' => oldest_and_latest,
  'tvos-swift' => oldest_and_latest,

  'osx-swift-evolution' => latest_only,
  'ios-swift-evolution' => latest_only,
  'tvos-swift-evolution' => latest_only,

  'catalyst' => oldest_and_latest,
  'catalyst-swift' => oldest_and_latest,

  'xcframework' => latest_only,

  'cocoapods-osx' => all,
  'cocoapods-ios' => oldest_and_latest,
  'cocoapods-ios-dynamic' => oldest_and_latest,
  'cocoapods-watchos' => oldest_and_latest,
  # 'cocoapods-catalyst' => oldest_and_latest,
  'swiftui-ios' => latest_only,
  'swiftui-server-osx' => latest_only,
}

output_file = "#!/bin/sh"
output_file << """
# This is a generated file produced by scripts/pr-ci-matrix.rb.

set -o pipefail

# Set the -e flag to stop running the script in case a command returns
# a non-zero exit code.
set -e

echo 'export GEM_HOME=$HOME/gems' >>~/.bash_profile
echo 'export PATH=$HOME/gems/bin:$PATH' >>~/.bash_profile
export GEM_HOME=$HOME/gems
export PATH=\"$GEM_HOME/bin:$PATH\"

: '
xcode_version:#{XCODE_VERSIONS.map { |v| "\n - #{v}" }.join()}
target:#{targets.map { |k, v| "\n - #{k}" }.join()}
configuration:
 - N/A
'

# Dependencies
brew install moreutils

# CI Workflows
cd ..
"""

targets.each_with_index { |(name, filter), index|
  XCODE_VERSIONS.each { |version|
    if filter.call(version)
      output_file << """
: '
- xcode_version: #{version}
- target: #{name}
'
"""
      if index == 0
          output_file << "if [ \"$CI_WORKFLOW\" = \"#{name}_#{version}\" ]; then\n"
      else
          output_file << "elif [ \"$CI_WORKFLOW\" = \"#{name}_#{version}\" ]; then\n"
      end
      output_file << "     export target=\"#{name}\"\n"
      output_file << "     sh -x build.sh ci-pr | ts\n"

      if index == targets.size - 1
          output_file << "elif [ \"$CI_WORKFLOW\" = \"Realm-Latest\" ] || [ \"$CI_WORKFLOW\" = \"RealmSwift-Latest\" ]; then\n"
          output_file << "     echo \"CI workflows for testing latest XCode releases\"\n"
          output_file << "else\n"
          output_file << "     set +e\n"
          output_file << "     exit 1\n"
          output_file << "fi\n"
      end
    end
  }
}

File.open('ci_scripts/ci_post_clone.sh', "w") do |file|
  file.puts output_file
end
