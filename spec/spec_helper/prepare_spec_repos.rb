#!/usr/bin/env ruby
def cocoapods_generate_specs_cp_repos_dir
  Pathname(__dir__).parent.join('integration', 'specs-repos')
end

def cocoapods_generate_specs_prepare_spec_repos
  require 'cocoapods/executable'

  cocoapods_generate_specs_cp_repos_dir.each_child do |c|
    next unless File.exist?(c.join('url'))
    FileUtils.rm_rf c.join('.git')

    Pod::Executable.capture_command(:git, ['init', c.to_s])
    c.join('.git', 'config').write %([remote "origin"]\n\turl = #{c.join('url').read.strip}\n)
  end
end
