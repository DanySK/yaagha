# Yet Another Automerge GitHub Action
### (but this one works better, of course)

This work has been inspired by [pascalgn/automerge-action](https://github.com/pascalgn/automerge-action),
which I used for a long time before taking over and writing this that better fits my needs.

## Input parameters and configuration

This action (by design choice, mostly due to portability) does not rely on GitHub inputs, but uses environment variables.

* `GITHUB_TOKEN`: **Mandatory**, GitHub authentication token. Usually set to `${{ secrets.GITHUB_TOKEN }}`.
* `MERGE_FORKS`: Whether pull requests coming from repositories other than `GITHUB_REPOSITORY` should be considered for an automatic merge. Defaults to `false`.
Anything but `true` (ignoring case) is interpreted as `false`.
* `MERGE_LABELS`: List of comma separated labels that must be present on a pull request for Yaagha to run the merge operation, defaults to `automerge`.
* `BLOCK_LABELS`: List of comma separated labels that, if present, prevents automatic merging. Default empty. Block labels take priority over merge labels.
* `MERGE_METHOD`: How to merge, between `merge`, `rebase`, and `squash`. Defaults to `merge`.
* `FALLBACK_TO_MERGE`: In case the `MERGE_METHOD` is not `merge`, whether to perform a merge anyway if the pull request is `mergeable` but not `rebaseable`
* `AUTO_UPDATE`: Whether pull requests coming from this repository should get updated before merge. Defaults to `true`.
Anything but `true` (ignoring case) is interpreted as `false`.
* `MERGE_WHEN_BEHIND`: if `AUTO_UPDATE` is disabled, Whether to merge pull requests that are in mergeable state `behind`. Defaults to `false`
Anything but `true` (ignoring case) is interpreted as `false`.
* `CLOSE_ON_CONFLICT`: Closes the pull request if it can't get updated (mergeable state `dirty`). Defaults to `false`.
Anything but `true` (ignoring case) is interpreted as `false`.
* `DELETE_BRANCH_ON_CLOSE`: if the pull request does not come from a fork and both `AUTO_UPDATE` and `CLOSE_ON_CONFLICT` are set, this flag determines whether the head branch should get deleted.
Defaults to `false`.
Anything but `true` (ignoring case) is interpreted as `false`.
The same behavior in case of successful merge can be achieved by configuring "Automatically delete head branches" in the repository's options. 
* `GIT_USER_NAME`: Name of the committer, to be used in case of rebase update. Defaults to `yaagha [bot]`
* `GIT_USER_EMAIL`: Email of the committer, to be used in case of rebase update. Defaults to `yaagha@automerge.bot`

### Additional configuration options

These options are available, but the average user will probably never need to mess with them.

* `GITHUB_API_URL`: API endpoint. Defaults to `https://api.github.com`
* `GITHUB_REPOSITORY`: Repository where this action is being run. Automatically populated by GitHub Actions.
* `GITHUB_SERVER_URL`: GitHub server URL. Defaults to `https://github.com`
* `GITHUB_WORKSPACE`: Internal work directory. Automatically populated by GitHub Actions.


## Usage example

Yaagha uses yaagha to keep itself up to date. Just look at [this file](https://github.com/DanySK/yaagha/blob/master/.github/workflows/automerge.yml) for a working configuration.
