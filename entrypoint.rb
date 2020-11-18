#!/usr/bin/env ruby
require 'rubygems'
require 'bundler/setup'
require 'octokit'

# Run label evaluation first
def parse_label_list(labels)
    labels.split(',').map(&:strip)
end
allow_labels = parse_label_list(ENV['MERGE_LABELS'] || 'automerge')
block_labels = parse_label_list(ENV['BLOCK_LABELS'] || '')
label_intersection = allow_labels.intersection(block_labels)
unless label_intersection.empty? then
    raise("Inconsistent configuration: labels #{label_intersection} are both in MERGE_LABELS and BLOCK_LABELS")
end

# Common configuration
puts 'Checking input parameters'
github_token = ENV['GITHUB_TOKEN'] || raise('No GitHub token provided')
github_api_endpoint = ENV['GITHUB_API_URL'] || 'https://api.github.com'
puts "Configuring API access, selected endpoint is #{github_api_endpoint}"
Octokit.configure do | conf |
    conf.api_endpoint = github_api_endpoint
end
puts 'Authenticating with GitHub...'

client = Octokit::Client.new(:access_token => github_token)

# 1. Check if this repository has open pull requests
repo_slug = ENV['GITHUB_REPOSITORY'] || raise('Mandatory GITHUB_REPOSITORY environment variable unset')
open_pull_requests = client.pull_requests(repo_slug)
if (open_pull_requests.empty?) then
    exit(0)
end
# 2. Filter pull requests by label and head repo
should_merge_forks = (ENV['MERGE_FORKS'] || 'false').casecmp('true').zero?
pull_requests = open_pull_requests.filter do | pull_request |
    labels = pull_request.labels.map(&:name)
    labels.intersection(allow_labels) == allow_labels && # All labels are there
        labels.intersection(block_labels).empty? && # No blocking labels are there
        !pull_request.locked &&
        # Either it's ok to merge forks or head and base repo should be equal
        (should_merge_forks || pull_request.base.repo.full_name == pull_request.head.repo.full_name)
end

def truth_of(value, default)
    (value || default).casecmp(default.to_s).zero?
end

should_update = truth_of(ENV['AUTO_UPDATE'], true)
close_on_conflict = truth_of(ENV['CLOSE_ON_CONFLICT'], false)
delete_branch_on_close = truth_of(ENV['DELETE_BRANCH_ON_CLOSE'], false)
merge_behind = truth_of(ENV[`MERGE_WHEN_BEHIND`], true)
merge_method = ENV['MERGE_METHOD'] || 'merge'
pull_requests.each do | pull_request |
    case pull_request.mergeable_state
    when 'behind'
        if should_update then
            client.put("/repos/#{repo_slug}/pulls/#{pull_request.number}/update-branch", :accept => 'application/vnd.github.lydian-preview+json')
        elsif merge_behind
            client.merge_pull_request(repo_slug, pull_request.number, pull_request.title, { :merge_method => merge_method })
        end
    when 'clean'
        client.merge_pull_request(repo_slug, pull_request.number, pull_request.title, { :merge_method => merge_method })
    when 'dirty'
        if close_on_conflict then
            client.update_pull_request(repo_slug, pull_request.number, { :state => 'closed' })
            if delete_branch_on_close then
                client.delete_branch(repo_slug, pull_request.head.ref)
            end
        end
    else
        puts "Unknown mergeable_state '#{pull_request.mergeable_state}'"
    end
end
