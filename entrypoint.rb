#!/usr/bin/env ruby
require 'rubygems'
require 'bundler/setup'
require 'octokit'
require 'git'

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
    (value || default.to_s).casecmp('true').zero?
end

should_update = truth_of(ENV['AUTO_UPDATE'], true)
close_on_conflict = truth_of(ENV['CLOSE_ON_CONFLICT'], false)
delete_branch_on_close = truth_of(ENV['DELETE_BRANCH_ON_CLOSE'], false)
merge_behind = truth_of(ENV['MERGE_WHEN_BEHIND'], true)
fallback_to_merge = truth_of(ENV['FALLBACK_TO_MERGE'], false)
merge_method = ENV['MERGE_METHOD'] || 'merge'

def update_rebase(client, pull_request)
    repo = pull_request.base.repo
    base_branch = pull_request.base.ref
    head_branch = pull_request.head.ref
    # Clone the repository
    destination = Dir["#{ENV['GITHUB_WORKSPACE']}/#{repo.full_name}"]
    git = Git.clone(repo.html_url, destination)
    puts git.checkout(head_branch)
    successful_rebase = Dir.chdir(destination) do
        rebase = `git rebase --autosquash master`
        if rebase.include?('CONFLICT') then
            puts rebase
            puts 'Unable to perform rebase, considering the pull request as dirty'
            `git rebase --abort`
            false
        else
            puts `git push --force`
            $?.success?
        end
    end
    FileUtils.rm_rf(destination)
    unless successful_rebase then
        puts 'Rebase failed, treating this repository as dirty'
        dirty(client, pull_request)
    end
end

def perform_merge(client, pull_request)
    rebaseable = pull_request.rebaseable
    if rebaseable || pull_request.mergeable && (merge_method == 'merge' || fallback_to_merge)  then
        client.merge_pull_request(repo_slug, pull_request.number, pull_request.title, { :merge_method => merge_method })
    else
        puts "Pull request ##{pull_request.number} can't get merged with method #{merge_method}."
        puts "Rebaseable: #{rebaseable}; mergeable: #{pull_request.mergeable}"
        puts 'Treating the pull request as dirty'
        dirty(client, pull_request)
    end
end

def behind(client, pull_request)
    if should_update then
        if merge_method == 'merge' then
            client.put("/repos/#{repo_slug}/pulls/#{pull_request.number}/update-branch", :accept => 'application/vnd.github.lydian-preview+json')
        elsif pull_request.base.repo.full_name == pull_request.head.repo.full_name
            update_rebase(client, pull_request)
        end
    elsif merge_behind
        perform_merge(client, pull_request)
    end
end

def dirty(client, pull_request)
    if close_on_conflict then
        client.update_pull_request(repo_slug, pull_request.number, { :state => 'closed' })
        if delete_branch_on_close then
            client.delete_branch(repo_slug, pull_request.head.ref)
        end
    end
end

pull_requests.each do | pull_request |
    puts "Process ##{pull_request.number}: #{pull_request.title}"
    # Request a pull request descriptor including the mergeable state
    pull_request = client.pull_request(repo_slug, pull_request.number)
    state = pull_request.mergeable_state
    puts "Pull request ##{pull_request.number} is in state '#{state}'"
    case pull_request.mergeable_state
    when 'behind'
        behind(client, pull_request)
    when 'clean'
        perform_merge(client, pull_request)
    when 'dirty'
        dirty(client, pull_request)
    # when 'unknown'
    #     puts 'Trying to syncronize'
    #     behind(client, pull_request)
    #     puts "Reloading the pull request"
    #     pull_request = client.pull_request(repo_slug, pull_request.number)
    else
        puts "Skipping pull request with mergeable_state '#{pull_request.mergeable_state}'"
    end
end
