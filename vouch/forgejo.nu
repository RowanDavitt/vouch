# Forgejo API utilities and CLI commands for Nu scripts

use file.nu [default-path, "from td", init-file, open-file, "to td"]
use git.nu [commit-and-push]
use codeowners.nu [parse-codeowners]
use lib.nu [
  add-user
  check-user
  denounce-user
  parse-comment
  remove-user
]

use template.nu
const pr_template = path self ./templates/forgejo-pr-unvouched
const issue_template = path self ./templates/forgejo-issue-unvouched

# Check if a PR author is a vouched contributor.
#
# This checks if the PR author is:
#   1. A bot (ends with [bot])
#   2. A collaborator with write access
#   3. In the vouched contributors list
#   4. Denounced
#
# When --require-vouch is true (default), unvouched users are blocked.
# When --require-vouch is false, only denounced users are blocked.
#
# When --auto-close is true and user is unvouched/denounced, the PR is closed.
#
# --template-file can be used to supply a path to a custom template, which
# follows the string convention as seen in Nushell's "format pattern". Note the
# following template arguments are supported:
#
#   * {author} - The pull request author
#   * {owner} - The repository owner
#   * {repo} - The repository name
#   * {default_branch} - The repository default branch
# 
# See "vouch/templates/forgejo-pr-unvouched" for the default PR template, which
# can be used as an example.
#
# Outputs status: "skipped" (bot), "vouched", "allowed", or "closed".
#
# Examples:
#
#   # Check PR author status (dry run)
#   ./vouch.nu gh-check-pr 123
#
#   # Auto-close unvouched PRs
#   ./vouch.nu gh-check-pr 123 --auto-close --dry-run=false
#
#   # Allow unvouched users, only block denounced
#   ./vouch.nu gh-check-pr 123 --require-vouch=false --auto-close
#
export def fj-check-pr [
  pr_number: int,              # Forgejo PR number
  --repo (-R): string,         # Repository in "owner/repo" format (required)
  --api_url(-A): string,       # Url for api requests (defaults to --platform+default_api_path)
  --platform_url (-P): string, # Url for Forgejo instance
  --vouched-repo: string,      # Repository for the vouched file (defaults to --repo)
  --vouched-file: string = ".forgejo/VOUCHED.td", # Path to vouched contributors file in the repo
  --template-file: string = $pr_template,        # Optional path to response template to use for unvouched users
  --require-vouch = true,      # Require users to be vouched (false = only block denounced)
  --auto-close = false,        # Automatically close PRs from unvouched/denounced users
  --dry-run = true,            # Print what would happen without making changes
] {
  if ($repo | is-empty) {
    error make { msg: "--repo is required" }
  }
  if ($api_url | is-empty) { 
    error make { msg: "--api_url is required" } 
  }
  let platform = canon_platform $platform_url $api_url

  let repo_parts = ($repo | split row "/" | {owner: $in.0, name: $in.1})

  let pr_data = api "get" $api_url $"/repos/($repo_parts.owner)/($repo_parts.name)/pulls/($pr_number)"
  let pr_author = $pr_data.user.login
  let default_branch = $pr_data.base.repo.default_branch

  let result = (fj-check-user $pr_author
    -R $repo
    -A $api_url
    -P $platform
    --vouched-repo $vouched_repo
    --vouched-file $vouched_file
    --default-branch $default_branch)

  if $result.status == "bot" {
    print $"($pr_author) is a bot, skipping"
    return "skipped"
  }

  if $result.status == "collaborator" {
    print $"($pr_author) is a collaborator with ($result.permission) access"
    return "vouched"
  }

  if $result.status == "vouched" {
    print $"($pr_author) is in the vouched contributors list"
    return "vouched"
  }

  if $result.status == "denounced" {
    print $"($pr_author) is denounced"

    if not $auto_close {
      return "closed"
    }

    print "Closing PR"

    let message = "This PR has been automatically closed because the author is explicitly blocked in the vouch list."

    if $dry_run {
      print "(dry-run) Would post comment and close PR"
      return "closed"
    }

    api "post" $api_url $"/repos/($repo_parts.owner)/($repo_parts.name)/issues/($pr_number)/comments" {
      body: $message
    }

    api "patch" $api_url $"/repos/($repo_parts.owner)/($repo_parts.name)/pulls/($pr_number)" {
      state: "closed"
    }

    return "closed"
  }

  print $"($pr_author) is not vouched"

  if not $require_vouch {
    print $"($pr_author) is allowed (char lparen)vouch not required(char rparen)"
    return "allowed"
  }

  if not $auto_close {
    return "closed"
  }

  print "Closing PR"

  let message = {
    author: $pr_author,
    owner: $repo_parts.owner,
    repo: $repo_parts.name,
    default_branch: $default_branch,
    platform: $platform
  } | template render (if ($template_file | is-not-empty) { $template_file } else $pr_template)

  if $dry_run {
    print "(dry-run) Would post comment and close PR"
    return "closed"
  }

  api "post" $api_url $"/repos/($repo_parts.owner)/($repo_parts.name)/issues/($pr_number)/comments" {
    body: $message
  }

  api "patch" $api_url $"/repos/($repo_parts.owner)/($repo_parts.name)/pulls/($pr_number)" {
    state: "closed"
  }

  return "closed"
}

# Check if an issue reporter is a vouched contributor.
#
# This checks if the issue author is:
#   1. A bot (ends with [bot])
#   2. A collaborator with write access
#   3. In the vouched contributors list
#   4. Denounced
#
# When --require-vouch is true (default), unvouched users are blocked.
# When --require-vouch is false, only denounced users are blocked.
#
# When --auto-close is true and user is unvouched/denounced, the issue is closed.
#
# --template-file can be used to supply a path to a custom template, which
# follows the string convention as seen in Nushell's "format pattern". Note the
# following template arguments are supported:
#
#   * {author} - The issue author
#   * {owner} - The repository owner
#   * {repo} - The repository name
#   * {default_branch} - The repository default branch
# 
# See "vouch/templates/forgejo-issue-unvouched" for the default issue template,
# which can be used as an example.
#
# Outputs status: "skipped" (bot), "vouched", "allowed", or "closed".
#
# Examples:
#
#   # Check issue author status (dry run)
#   ./vouch.nu gh-check-issue 123
#
#   # Auto-close unvouched issues
#   ./vouch.nu gh-check-issue 123 --auto-close --dry-run=false
#
#   # Allow unvouched users, only block denounced
#   ./vouch.nu gh-check-issue 123 --require-vouch=false --auto-close
#
export def fj-check-issue [
  issue_number: int,             # Forgejo issue number
  --repo (-R): string,           # Repository in "owner/repo" format (required)
  --api_url (-A): string,        # Url for api requests
  --platform_url (-P): string,   # Url for the Forgejo instance
  --vouched-repo: string,        # Repository for the vouched file (defaults to --repo)
  --vouched-file: string = ".forgejo/VOUCHED.td", # Path to vouched contributors file in the repo
  --template-file: string = $issue_template,     # Optional path to response template to use for unvouched users
  --require-vouch = true,        # Require users to be vouched (false = only block denounced)
  --auto-close = false,          # Automatically close issues from unvouched/denounced users
  --dry-run = true,              # Print what would happen without making changes
] {
  if ($repo | is-empty) {
    error make { msg: "--repo is required" }
  }
  if ($api_url | is-empty) { 
    error make { msg: "--api_url is required" } 
  }
  let platform = canon_platform $platform_url $api_url

  let owner = ($repo | split row "/" | first)
  let repo_name = ($repo | split row "/" | last)

  let issue_data = api "get" $api_url $"/repos/($owner)/($repo_name)/issues/($issue_number)"
  let issue_author = $issue_data.user.login
  let default_branch = try { $issue_data.repository.default_branch } catch {
    let repo_data = api "get" $api_url $"/repos/($owner)/($repo_name)"
    $repo_data.default_branch
  }

  let result = (fj-check-user $issue_author
    -R $repo
    -A $api_url
    -P $platform
    --vouched-repo $vouched_repo
    --vouched-file $vouched_file
    --default-branch $default_branch)

  if $result.status == "bot" {
    print $"($issue_author) is a bot, skipping"
    return "skipped"
  }

  if $result.status == "collaborator" {
    print $"($issue_author) is a collaborator with ($result.permission) access"
    return "vouched"
  }

  if $result.status == "vouched" {
    print $"($issue_author) is in the vouched contributors list"
    return "vouched"
  }

  if $result.status == "denounced" {
    print $"($issue_author) is denounced"

    if not $auto_close {
      return "closed"
    }

    print "Closing issue"

    let message = "This issue has been automatically closed because the author is explicitly blocked in the vouch list."

    if $dry_run {
      print "(dry-run) Would post comment and close issue"
      return "closed"
    }

    api "post" $api_url $"/repos/($owner)/($repo_name)/issues/($issue_number)/comments" {
      body: $message
    }

    api "patch" $api_url $"/repos/($owner)/($repo_name)/issues/($issue_number)" {
      state: "closed",
      state_reason: "not_planned",
    }

    return "closed"
  }

  print $"($issue_author) is not vouched"

  if not $require_vouch {
    print $"($issue_author) is allowed (char lparen)vouch not required(char rparen)"
    return "allowed"
  }

  if not $auto_close {
    return "closed"
  }

  print "Closing issue"

  let message = {
    author: $issue_author,
    owner: $owner,
    repo: $repo_name,
    default_branch: $default_branch,
  } | template render (if ($template_file | is-not-empty) { $template_file } else $issue_template)

  if $dry_run {
    print "(dry-run) Would post comment and close issue"
    return "closed"
  }

  api "post" $api_url $"/repos/($owner)/($repo_name)/issues/($issue_number)/comments" {
    body: $message
  }

  api "patch" $api_url $"/repos/($owner)/($repo_name)/issues/($issue_number)" {
    state: "closed",
    state_reason: "not_planned",
  }

  return "closed"
}

# Manage contributor status via issue comments.
#
# This checks if a comment matches a vouch keyword (default: "vouch"),
# denounce keyword (default: "denounce"), or unvouch keyword (default:
# "unvouch"), verifies the commenter has sufficient permissions, and
# updates the vouched list accordingly.
#
# Permission is checked using role_name from the collaborator API.
# When --roles is empty (default), the legacy permission field is
# also accepted if it is "admin" or "write".
#
# For vouch, the comment can be:
#   - "vouch" - vouches the issue author
#   - "vouch @user" - vouches the specified user
#   - "vouch <reason>" - vouches the issue author with a reason
#   - "vouch @user <reason>" - vouches the specified user with a reason
#
# For denounce, the comment can be:
#   - "denounce" - denounces the issue author
#   - "denounce @user" - denounces the specified user
#   - "denounce <reason>" - denounces the issue author with a reason
#   - "denounce @user <reason>" - denounces the specified user with a reason
#
# For unvouch, the comment can be:
#   - "unvouch" - removes the issue author
#   - "unvouch @user" - removes the specified user
#
# Use --vouch-keyword, --denounce-keyword, and --unvouch-keyword to
# customize the trigger words. Multiple keywords can be specified as a list.
#
# Outputs a status to stdout: "vouched", "denounced", "unvouched", or "unchanged"
#
# Examples:
#
#   # Dry run (default) - see what would happen
#   ./vouch.nu gh-manage-by-issue 123 456789
#
#   # Actually perform the action
#   ./vouch.nu gh-manage-by-issue 123 456789 --dry-run=false
#
#   # Custom vouch keywords
#   ./vouch.nu gh-manage-by-issue 123 456789 --vouch-keyword [lgtm approve]
#
#   # Create a pull request instead of pushing directly
#   ./vouch.nu gh-manage-by-issue 123 456789 --pull-request --dry-run=false
#
export def fj-manage-by-issue [
  issue_id: int,           # GitHub issue number
  comment_id: int,         # GitHub comment ID
  --repo (-R): string,     # Repository in "owner/repo" format (required)
  --platform_url (-P): string       # Url for Forgejo instance
  --api_url (-A): string,       # Url for api requests (defaults to --platform+default_api_path)
  --vouched-file: string = "",  # Path to vouched contributors file (default: VOUCHED.td or .github/VOUCHED.td)
  --vouch-keyword: list<string> = [], # Keywords that trigger vouching (default: ["vouch"])
  --denounce-keyword: list<string> = [], # Keywords that trigger denouncing (default: ["denounce"])
  --unvouch-keyword: list<string> = [], # Keywords that trigger unvouching (default: ["unvouch"])
  --allow-vouch = true,   # Enable vouch handling
  --allow-denounce = true, # Enable denounce handling
  --allow-unvouch = true,  # Enable unvouch handling
  --roles: list<string> = [], # Allowed role names (default: [admin maintain write triage])
  --vouched-managers: record, # Optional managers file config
  --commit = true,         # Commit and push changes
  --commit-message: string = "", # Git commit message
  --pull-request = false,  # Create a pull request instead of pushing directly
  --merge-immediately = false, # Merge the pull request immediately after creation
  --dry-run = true,        # Print what would happen without making changes
] {
  if ($repo | is-empty) {
    error make { msg: "--repo is required" }
  }
  if ($api_url | is-empty) { 
    error make { msg: "--api_url is required" } 
  }
  let platform = canon_platform $platform_url $api_url

  let file = resolve-vouched-file $vouched_file

  let owner = ($repo | split row "/" | first)
  let repo_name = ($repo | split row "/" | last)
  let issue_data = (
    api "get" $api_url
      $"/repos/($owner)/($repo_name)/issues/($issue_id)"
  )
  let comment_data = (
    api "get" $api_url
      $"/repos/($owner)/($repo_name)/issues/comments/($comment_id)"
  )

  let issue_author = $issue_data.user.login
  let commenter = $comment_data.user.login
  let comment_body = (
    $comment_data.body | default "" | str trim
  )

  # get the comment url here instead of reconstructing it later
  let comment_url = $comment_data.html_url

  let vouch_keywords = if ($vouch_keyword | is-empty) {
    ["vouch"]
  } else {
    $vouch_keyword
  }
  let denounce_keywords = if ($denounce_keyword | is-empty) {
    ["denounce"]
  } else {
    $denounce_keyword
  }
  let unvouch_keywords = if ($unvouch_keyword | is-empty) {
    ["unvouch"]
  } else {
    $unvouch_keyword
  }

  let parsed = (parse-comment $comment_body
    --vouch-keyword $vouch_keywords
    --denounce-keyword $denounce_keywords
    --unvouch-keyword $unvouch_keywords
    --allow-vouch=$allow_vouch
    --allow-denounce=$allow_denounce
    --allow-unvouch=$allow_unvouch)

  if $parsed.action == null {
    print "Comment does not match any enabled action"
    return "unchanged"
  }

  if not (
    can-manage $commenter $platform $owner $repo_name
      --roles $roles
      --vouched-managers $vouched_managers
  ) {
    print $"($commenter) does not have sufficient access"
    return "unchanged"
  }

  let target_user = $parsed.user | default $issue_author
  let prior = open -r $file
  let result = (fj-apply-action $platform
    $parsed.action $target_user $parsed.reason $file
    --dry-run=$dry_run)

  if $result.acted and $commit {
    if $pull_request {
      let branch = (commit-and-push $file
        --message $commit_message
        --branch "vouch/")
      let title = (
        $commit_message
        | default -e "Update VOUCHED list"
        | lines
        | first
      )
      let body = $"Triggered by [comment]\(($comment_url)\) from @($commenter).\n\n($parsed.action | str capitalize): @($target_user)"
      open-pr $api_url $owner $repo_name $branch $title $body --merge-immediately=$merge_immediately
    } else {
      (commit-and-push $file
        --message $commit_message
        --retry 3
        --retry-action {
          $prior | save -f $file
          fj-apply-action platform (
            $parsed.action
          ) $target_user $parsed.reason $file
        })
    }
    try { react $owner $api_url $repo_name $comment_id "+1" }
  }

  $result.status
}


# Sync CODEOWNERS entries into the vouched list.
#
# This reads the CODEOWNERS file, expands any team owners to their
# members, and ensures those users are vouched in the VOUCHED file.
#
# This will only ADD users to the vouched list, it doesn't unvouch
# anyone. This is because its impossible to tell who was vouched 
# separately from being a codeowner, so we want to avoid accidentally 
# unvouching users if the CODEOWNERS file or team membership is changed.
#
# Note that if a user is denounced, this will replace them with a
# vouched user, because we expect that everyone in a codeowner is
# trusted.
#
# When --dry-run is true (default), no changes are written.
#
# Outputs status: "updated" or "unchanged".
export def fj-sync-codeowners [
  --repo (-R): string,        # Repository in "owner/repo" format
  --platform_url (-P): string,        # Url for Forgejo instance
  --api_url (-A): string,         # Url for api requests
  --codeowners-file: string = "", # Path to CODEOWNERS file
  --vouched-file: string = "", # Path to vouched contributors file
  --commit = true,            # Commit and push changes
  --commit-message: string = "", # Git commit message
  --pull-request = false,     # Create a pull request instead of pushing
  --merge-immediately = false, # Merge the pull request after creation
  --dry-run = true,           # Print what would happen without changes
] {
  if ($repo | is-empty) {
    error make { msg: "--repo is required" }
  }
  if ($api_url | is-empty) { 
    error make { msg: "--api_url is required" } 
  }
  let platform = canon_platform $platform_url $api_url

  let owner = ($repo | split row "/" | first)
  let repo_name = ($repo | split row "/" | last)
  let codeowners_path = resolve-codeowners-file $codeowners_file
  let file = resolve-vouched-file $vouched_file

  # Parse the CODEOWNERS file and extract all owner handles.
  let handles = (
    open -r $codeowners_path
      | parse-codeowners
      | get owner
  )

  # Separate handles into team paths (org/team) and
  # individual user handles.
  let team_paths = (
    $handles
    | where { |o| $o | str contains "/" }
  )
  let user_handles = (
    $handles
    | where { |o| not ($o | str contains "/") }
  )

  # Resolve team paths into individual members by querying
  # the Forgejo API for each team's membership.
  mut team_members = []
  for team_path in $team_paths {
    let parts = ($team_path | split row "/" --number 2)
    let org = ($parts | first)
    let team = ($parts | get 1)
    let members = fj-team-members $api_url $org $team
    $team_members = ($team_members | append $members)
  }

  # Combine individual handles and resolved team members
  # into a single deduplicated list of users.
  let users = (
    $user_handles
    | append $team_members
    | uniq
  )

  if ($users | is-empty) {
    error make { msg: "No codeowner users found." }
  }

  if not ($file | path exists) {
    init-file $file
  }

  # Walk through each codeowner user and add them to the
  # vouched list if they aren't already vouched.
  let records = open-file $file
  mut updated = $records
  mut added = []
  for user in $users {
    let status = (
      $updated
      | check-user $user --default-platform $platform
    )

    if $status != "vouched" {
      $updated = (
        $updated
        | add-user $user --default-platform $platform
      )
      $added = ($added | append $user)
    }
  }

  # If nothing changed, bail early.
  let changed = ($added | is-not-empty)
  if not $changed {
    print "All CODEOWNERS users are already vouched"
    return "unchanged"
  }

  let added_users = ($added | uniq | sort -i)

  if $dry_run {
    print (
      "(dry-run) Would add "
      + $"($added_users | length) "
      + "CODEOWNERS users to the VOUCHED list"
    )
    return "updated"
  }

  # Write the updated vouched list to disk.
  $updated | to td | save -f $file
  print (
    $"Added ($added_users | length) CODEOWNERS "
    + $"users to ($file)"
  )

  let message = (
    $commit_message
    | default -e "Sync CODEOWNERS vouch list"
  )

  # Commit and optionally push or open a PR. When pushing
  # directly (no PR), a retry action re-applies the additions
  # on top of the latest file in case of concurrent updates.
  if $commit {
    if $pull_request {
      let branch = (commit-and-push $file
        --message $message
        --branch "vouch/")
      let title = ($message | lines | first)
      let user_list = (
        $added_users
        | each { |u| $"- @($u)" }
        | str join "\n"
      )
      let body = ([
        $"Sync CODEOWNERS owners with vouch list."
        ""
        "## Added Users"
        ""
        $user_list
      ] | str join "\n")
      (open-pr $api_url $owner $repo_name $branch $title $body
        --merge-immediately=$merge_immediately)
    } else {
      let to_add = $added_users
      (commit-and-push $file
        --message $message
        --retry 3
        --retry-action {
          let current = open-file $file
          mut retry_records = $current
          for user in $to_add {
            $retry_records = (
              $retry_records
              | add-user $user --default-platform $platform
            )
          }
          $retry_records | to td | save -f $file
        })
    }
  }

  "updated"
}

# Resolve the CODEOWNERS file path, falling back to defaults.
def resolve-codeowners-file [codeowners_file: string] {
  if ($codeowners_file | is-not-empty) {
    if not ($codeowners_file | path exists) {
      error make {
        msg: $"CODEOWNERS file not found: ($codeowners_file)"
      }
    }
    return $codeowners_file
  }

  if ("CODEOWNERS" | path exists) {
    return "CODEOWNERS"
  }

  if (".foregjo/CODEOWNERS" | path exists) {
    return ".foregjo/CODEOWNERS"
  }

  error make { msg: "CODEOWNERS file not found" }
}

# Fetch all members of a Forgejo team (paginated).
def fj-team-members [api_url:string org: string, team: string] {
  mut page = 1
  mut members = []

  loop {
    let result = (api "get" $api_url (
      $"/orgs/($org)/teams/($team)/members?"
      + $"per_page=100&page=($page)"
    ))

    if ($result | is-empty) {
      break
    }

    let logins = ($result | each { |item| $item.login })
    $members = ($members | append $logins)
    $page += 1
  }

  $members | uniq
}

# Resolve the vouched file path, falling back to default-path or .foregjo/VOUCHED.td.
def resolve-vouched-file [vouched_file: string] {
  if ($vouched_file | is-not-empty) {
    return $vouched_file
  }

  let default = default-path
  if ($default | is-empty) {
    ".foregjo/VOUCHED.td"
  } else {
    $default
  }
}

# Apply a vouch, denounce, or unvouch action to the vouched file.
#
# Returns a record with:
#   - status: "vouched", "denounced", "unvouched", or "unchanged"
#   - acted: true if a real change was made (not dry-run, not already in desired state)
def fj-apply-action [
  platform: string,        # URL of of the Forgejo instance
  action: string,          # "vouch", "denounce", or "unvouch"
  target_user: string,     # Forgejo username to act on
  reason: string,          # Reason for the action (may be empty)
  file: string,            # Path to the vouched file
  --dry-run = false,       # Whether this is a dry run
] {
  if not ($file | path exists) {
    init-file $file
  }

  let records = open-file $file

  if $action == "vouch" {
    let status = $records | check-user $target_user --default-platform $platform
    if $status == "vouched" {
      print $"($target_user) is already vouched"
      return { status: "unchanged", acted: false }
    }

    if $dry_run {
      print ("(dry-run) Would add " + $"($target_user) to ($file)")
      return { status: "vouched", acted: false }
    }

    let new_records = $records | add-user $target_user --default-platform $platform --details $reason
    $new_records | to td | save -f $file

    print $"Added ($target_user) to vouched contributors"
    return { status: "vouched", acted: true }
  }

  if $action == "denounce" {
    let status = $records | check-user $target_user --default-platform $platform
    if $status == "denounced" {
      print $"($target_user) is already denounced"
      return { status: "unchanged", acted: false }
    }

    if $dry_run {
      let entry = if ($reason | is-empty) { $"-($target_user)" } else { $"-($target_user) ($reason)" }
      print ("(dry-run) Would add " + $"($entry) to ($file)")
      return { status: "denounced", acted: false }
    }

    let new_records = $records | denounce-user $target_user $reason --default-platform $platform
    $new_records | to td | save -f $file

    print $"Denounced ($target_user)"
    return { status: "denounced", acted: true }
  }

  if $action == "unvouch" {
    let status = $records | check-user $target_user --default-platform $platform
    if $status == "unknown" {
      print $"($target_user) is not in the vouched contributors list"
      return { status: "unchanged", acted: false }
    }

    if $dry_run {
      print ("(dry-run) Would remove " + $"($target_user) from ($file)")
      return { status: "unvouched", acted: false }
    }

    let new_records = $records | remove-user $target_user --default-platform $platform
    $new_records | to td | save -f $file

    print $"Removed ($target_user) from vouched contributors"
    return { status: "unvouched", acted: true }
  }

  { status: "unchanged", acted: false }
}

# Check if a Forgejo user is vouched in the vouch file in the given 
# repository.
#
# Returns a record with:
#   - status: "bot", "collaborator", "vouched", "denounced", or "unknown"
#   - permission: collaborator permission level (only set for "collaborator" status)
#
# By default, collaborator permissions can short-circuit the check. Use
# `--allow-collaborator=false` when you only want file-based status.
export def fj-check-user [
  user: string,            # Forgejo username to check
  --platform_url (-P): string, # Url for Forgejo instance
  --api_url (-A): string,  # Url for api requests
  --repo (-R): string,     # Repository in "owner/repo" format
  --vouched-repo: string,  # Repository for the vouched file (defaults to --repo)
  --vouched-file: string,  # Path to vouched contributors file in the repo
  --vouched-ref: string,   # Git ref for the vouched file (defaults to repo default branch)
  --default-branch: string, # Default branch of the repo (fetched if not set)
  --allow-collaborator = true, # Allow collaborator permissions to short-circuit
] {
  let repo_parts = ($repo | split row "/" | {owner: $in.0, name: $in.1})
  let vr = if ($vouched_repo | default "" | is-empty) { $repo } else { $vouched_repo }
  let vouch_parts = ($vr | split row "/" | {owner: $in.0, name: $in.1})

  if ($api_url | is-empty) { 
    error make { msg: "--api_url is required" } 
  }
  let platform = canon_platform $platform_url $api_url

  # All usernames that end with [bot] are bots and we allow it. The `[]`
  # characters aren't valid at the time of writing this for user accounts.
  if ($user | str ends-with "[bot]") {
    return { status: "bot" }
  }

  # See if this user has special permissions for the target repo.
  if $allow_collaborator {
    let permission = try {
      (api "get" $api_url
        $"/repos/($repo_parts.owner)/($repo_parts.name)/collaborators/($user)/permission"
        | get permission)
    } catch {
      null
    }
    if $permission in ["admin", "owner", "write"] {
      return { status: "collaborator", permission: $permission }
    }
  }

  let branch = if ($vouched_ref | default "" | is-not-empty) {
    $vouched_ref
  } else if ($default_branch | default "" | is-not-empty) {
    $default_branch
  } else {
    (api "get" $api_url
      $"/repos/($vouch_parts.owner)/($vouch_parts.name)"
      | get default_branch)
  }

  # Grab the vouched file contents
  let records = try {
    let file_data = (api "get" $api_url
      $"/repos/($vouch_parts.owner)/($vouch_parts.name)/contents/($vouched_file)?ref=($branch)")
    ($file_data.content
      | str replace -a "\n" ""
      | decode base64
      | decode utf-8
      | from td)
  } catch {
    []
  }

  # Check the status using standard lib functions
  let vouch_status = $records | check-user $user --default-platform github
  { status: $vouch_status }
}

# Create a pull request from the given branch into the
# repository's default branch.
def open-pr [
  api_url: string, # Api to use
  owner: string,   # Repository owner
  repo: string,    # Repository name
  branch: string,  # Head branch name
  title: string,   # PR title
  body: string,    # PR body
  --merge-immediately = false, # Merge the PR immediately after creation
] {
  let repo_data = (
    api "get" $api_url $"/repos/($owner)/($repo)"
  )
  let base = $repo_data.default_branch

  let pr = api "post" $api_url $"/repos/($owner)/($repo)/pulls" {
    title: $title,
    body: $body,
    head: $branch,
    base: $base,
  }

  if $merge_immediately {
    api "put" $api_url (
      $"/repos/($owner)/($repo)/pulls/($pr.number)/merge"
    ) {
      merge_method: "squash",
    }

    # Delete the head branch after merge
    api "delete" $api_url (
      $"/repos/($owner)/($repo)/git/refs/heads/($branch)"
    )
  }
}

# Add a reaction emoji to a Forgejo issue comment using the Reactions API.
def react [owner: string, api_url: string, repo: string, comment_id: int, reaction: string] {
  api "post" $api_url $"/repos/($owner)/($repo)/issues/comments/($comment_id)/reactions" {
    content: $reaction
  }
}


# Make a Forgejo API request with proper headers.
#
# Retries on transient errors with exponential backoff.
# Retries up to 5 times with delays of
# 1s, 2s, 4s, 8s, 16s (~30s total).
#
# Retried status codes:
#   - 401/403: transient auth errors (e.g., Foregjo Actions
#     token propagation race)
#   - 429: rate limiting
#   - 5xx: server errors
def api [
  method: string,  # HTTP method (get, post, patch, etc.)
  api_url: string, # API url (e.g., https://codeberg.com/api/v1)
  endpoint: string # API endpoint (e.g., /repos/owner/repo/issues/1/comments)
  body?: record    # Optional request body
] {
  let url = $"($api_url)($endpoint)"
  let headers = [
    Authorization $"Bearer (get-token)"
    Accept "application/json"
  ]

  mut attempt = 0
  loop {
    let resp = (match $method {
      "get" => { http get --allow-errors $url --headers $headers | api-check-status },
      "post" => { http post --allow-errors $url --headers $headers --content-type application/json $body | api-check-status },
      "patch" => { http patch --allow-errors $url --headers $headers --content-type application/json $body | api-check-status },
      "put" => { http put --allow-errors $url --headers $headers --content-type application/json $body | api-check-status },
      "delete" => { http delete --allow-errors $url --headers $headers | api-check-status },
      _ => { error make { msg: $"Unsupported HTTP method: ($method)" } }
    })

    if (is-retryable $resp.status) and $attempt < 5 {
      $attempt += 1
      sleep (1sec * (2 ** ($attempt - 1)))
      continue
    }

    if $resp.status >= 400 {
      error make {
        msg: $"($resp.status) ($method | str upcase) ($url)"
      }
    }

    return $resp.body
  }
}

# Check if an HTTP status code is retryable.
#
# Retryable codes:
#   - 401/403: transient auth errors (Foregjo Actions token
#     propagation race)
#   - 429: rate limiting
#   - 5xx: server errors
def is-retryable [status: int]: nothing -> bool {
  ($status in [401, 403, 429] or $status >= 500)
}

# Extract HTTP status from metadata, returning a
# record with body and status fields.
def api-check-status [] {
  metadata access {|meta|
    {
      body: $in,
      status: ($meta
        | get -o http_response.status
        | default 200),
    }
  }
}

# Get Forgejo token from environment
def get-token [] {
  if ($env.FORGEJO_TOKEN? | is-not-empty) {
    return $env.FORGEJO_TOKEN
  }
  error make { msg: "FORGEJO_TOKEN was not set" }
}

# Check if a given Forgejo user can manage vouch status for a vouch
# file in the given target repository.
#
# If `--roles` is specified, only allow users with those specific
# roles to manage vouch status. If `--roles` is NOT explicitly
# specified to a non-empty list, this will default to 
# [admin, maintain, write, triage]. Additionally, the legacy
# permissions [admin, write] are always allowed. If roles is explicitly
# specified, legacy permissions are ignored unless they are explicitly 
# specified.
#
# If `--legacy-permissions` is specified, also check the legacy
# `permission` field of the permission Forgejo REST API. If this is not
# specified, the default value is [admin, write] only if `--roles` is
# not set.
#
# If `--vouched-managers` is set, the managers file is also checked.
# Anyone listed as "vouched" in that file can manage vouches.
# The record fields are:
#   - repo: owner/repo for the managers file (empty = target repo)
#   - file: path to the managers VOUCHED file (required)
#   - ref: git ref to read from (empty = default branch)
export def can-manage [
  username: string, # Username of the Forgejo user to check
  api_url: string,  # Url for api requests
  repo_owner: string, # Repository owner (e.g., "mitchellh") for vouch file
  repo_name: string, # Repository name (e.g., "vouch") for vouch file
  --roles: list<string>, # Roles to allow
  --legacy-permissions: list<string>, # Legacy permissions to allow
  --vouched-managers: record, # Optional managers file config
  --platform_url: string,  # Url for the Forgejo instance

] {
  let real_roles = $roles | default --empty [
    owner
    admin
    maintain
    write
    triage
  ]

  # For legacy perms, we always take the flag value if its non-empty.
  # If it is empty, we set a default only if roles is empty.
  let real_legacy_perms = if (not ($legacy_permissions | is-empty)) {
    $legacy_permissions
  } else if (
    $roles |
    default --empty [] |
    is-empty
  ) {
    [admin, write]
  } else {
    []
  }

  let api_perm = try {
    api "get" api_url $"/repos/($repo_owner)/($repo_name)/collaborators/($username)/permission"
  } catch {
    null
  }

  if $api_perm != null {
    let role_allowed = (($api_perm.role_name in $real_roles)
      or ($api_perm.permission in $real_legacy_perms))
    if $role_allowed {
      return true
    }
  }

  # No managers file configured, so the user isn't eligible.
  if ($vouched_managers | default null) == null {
    return false
  }

  # Managers file is required to evaluate eligibility.
  let file = $vouched_managers.file | default ""
  if ($file | is-empty) {
    return false
  }

  # Check only the managers file; collaborator status shouldn't bypass it.
  let repo = if ($vouched_managers.repo | default "" | is-empty) {
    $"($repo_owner)/($repo_name)"
  } else {
    $vouched_managers.repo
  }
  let result = (fj-check-user $username
    --repo $"($repo_owner)/($repo_name)"
    --api_url $api_url
    --platform_url $platform_url
    --vouched-repo $repo
    --vouched-file $file
    --vouched-ref ($vouched_managers.ref | default "")
    --allow-collaborator=false)
  $result.status == "vouched"
}

# Canonicalize platform
# - removes http(s):// from the start
# - converts to lower case
#
# Right now it uses the api_url if no platform is provded, 
# I'm not sure if thats a good idea since
def canon_platform [platform: string, api_url: string] {
  return ($platform 
    | default -e $api_url
    | str replace -r r#'^https?://'# "" 
    | str downcase )
}
