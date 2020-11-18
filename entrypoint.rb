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
def github_token()
    ENV['GITHUB_TOKEN'] || raise('No GitHub token provided')
end
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

def merge_method()
    ENV['MERGE_METHOD'] || 'merge'
end 

def update_rebase(client, pull_request)
    repo = pull_request.base.repo
    base_branch = pull_request.base.ref
    head_branch = pull_request.head.ref
    # Clone the repository
    destination = "#{ENV['GITHUB_WORKSPACE']}/#{repo.full_name}"
    git = Git.clone(repo.html_url, destination)
    git.config('user.name', ENV['GIT_USER_NAME'] || 'yaagha [bot]')
    git.config('user.email', ENV['GIT_USER_EMAIL'] || 'yaagha@automerge.bot')
    puts git.checkout(head_branch)
    successful_rebase = Dir.chdir(destination) do
        rebase = `git rebase --autosquash master`
        if rebase.include?('CONFLICT') then
            puts rebase
            puts 'Unable to perform rebase, considering the pull request as dirty'
            `git rebase --abort`
            false
        else
            remote_uri = "https://#{ENV['GITHUB_ACTOR']}:#{github_token}@#{repo.html_url.split('://').last}"
            authenticated_remote_name = 'authenticated'
            git.add_remote(authenticated_remote_name, remote_uri)
            puts `git push --force`
            # $?.success?
            true
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
    if rebaseable || pull_request.mergeable && (merge_method == 'merge' || truth_of(ENV['FALLBACK_TO_MERGE'], false))  then
        client.merge_pull_request(
            pull_request.base.repo.full_name,
            pull_request.number,
            pull_request.title,
            { :merge_method => merge_method }
        )
    else
        puts "Pull request ##{pull_request.number} can't get merged with method #{merge_method}."
        puts "Rebaseable: #{rebaseable}; mergeable: #{pull_request.mergeable}"
        puts 'Treating the pull request as dirty'
        dirty(client, pull_request)
    end
end

def behind(client, pull_request)
    if truth_of(ENV['AUTO_UPDATE'], true) then
        if merge_method == 'merge' then
            repo_slug = pull_request.base.repo.full_name
            client.put("/repos/#{repo_slug}/pulls/#{pull_request.number}/update-branch", :accept => 'application/vnd.github.lydian-preview+json')
        elsif pull_request.base.repo.full_name == pull_request.head.repo.full_name
            update_rebase(client, pull_request)
        end
    elsif truth_of(ENV['MERGE_WHEN_BEHIND'], true)
        perform_merge(client, pull_request)
    end
end

def dirty(client, pull_request)
    if truth_of(ENV['CLOSE_ON_CONFLICT'], false) then
        repo_slug = pull_request.base.repo.full_name
        client.update_pull_request(repo_slug, pull_request.number, { :state => 'closed' })
        if truth_of(ENV['DELETE_BRANCH_ON_CLOSE'], false) then
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
    when /behind|unknown/
        behind(client, pull_request)
    when 'clean'
        perform_merge(client, pull_request)
    when 'dirty'
        dirty(client, pull_request)
    when 'unknown'
        puts 'Trying to syncronize'
        behind(client, pull_request)
    else
        puts "Skipping pull request with mergeable_state '#{pull_request.mergeable_state}'"
    end
end
