namespace :api_keys do
  desc "Issue a new API key: rails api_keys:issue[label]"
  task :issue, [ :label ] => :environment do |_task, args|
    label = args[:label]
    abort "Usage: rails api_keys:issue[label]" if label.blank?

    _api_key, raw_token = ApiKey.issue!(label: label)

    puts "API key issued for #{label.inspect}:"
    puts raw_token
    puts "(This token will not be shown again — store it now.)"
  end
end
