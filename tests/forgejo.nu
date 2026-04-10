use std/assert

use ../vouch/forgejo.nu [
  can-manage
  fj-check-issue
  fj-check-pr
  fj-manage-by-issue
]

const REPO = "RowanDavitt/testing_vouch"
const API_URL = "https://codeberg.org/api/v1" 
const PLATFORM = "https://codeberg.org" 

# Skip the entire test if no token is available
def --env skip-without-token [] {
  if ($env.FORGEJO_TOKEN? | is-empty) {
    $env.FORGEJO_TOKEN = (open "./.direnv/.token")

    if ($env.FORGEJO_TOKEN? | is-empty) {
      error make {
        msg: "SKIP: gh CLI not authenticated"
      }
    }
  }
}

export def "test slow fj-check-pr owner is vouched" [] {
  skip-without-token
  # PR #1 is by RowanDavitt (repo owner / collaborator)
  let result = (
    fj-check-pr 1 -R $REPO -A $API_URL -P $PLATFORM --dry-run=true
  )
  assert equal $result "vouched"
}

export def "test slow fj-check-pr vouched contributor" [] {
  skip-without-token
  # PR #2 is by rowansalt (in the vouched list)
  let result = (
    fj-check-pr 2 -R $REPO -A $API_URL -P $PLATFORM --dry-run=true
  )
  assert equal $result "vouched"
}

export def "test slow fj-check-pr unvouched user blocked" [] {
  skip-without-token
  # PR #4 is by evil_rowan (not in the vouched list,
  # not a collaborator)
  let result = (
    fj-check-pr 4 -R $REPO -A $API_URL -P $PLATFORM --dry-run=true
  )
  assert equal $result "closed"
}

export def "test slow fj-check-pr unvouched allowed without require-vouch" [] {
  skip-without-token
  # PR #4 is by evil_rowan, with require-vouch=false
  let result = (
    fj-check-pr 4
      -R $REPO
      -A $API_URL
      -P $PLATFORM
      --require-vouch=false
      --dry-run=true
  )
  assert equal $result "allowed"
}

export def "test slow fj-check-pr auto-close dry-run" [] {
  skip-without-token
  # PR #4 is by evil_rowan, with auto-close + dry-run
  let result = (
    fj-check-pr 4
      -R $REPO
      -A $API_URL 
      -P $PLATFORM
      --auto-close=true
      --dry-run=true
  )
  assert equal $result "closed"
}

# this repo doesnt have any bots at the moment
#export def "test slow fj-check-pr bot is skipped" [] {
#  # PR #27 is by dependabot[bot]
#  let result = (
#    fj-check-pr 27 -R $REPO -A $API_URL -P $PLATFORM --dry-run=true
#  )
#  assert equal $result "skipped"
#}

export def "test slow fj-check-pr missing repo errors" [] {
  skip-without-token
  let result = (do {
    nu -c (
      'use vouch *; fj-check-pr 1 --dry-run=true'
    )
  } | complete)
  assert ($result.exit_code != 0)
}

# --- fj-check-issue ---

export def "test slow fj-check-issue owner is vouched" [] {
  skip-without-token
  # Issue #6 is by RowanDavitt (repo owner)
  let result = (
    fj-check-issue 6 -R $REPO -A $API_URL -P $PLATFORM --dry-run=true
  )
  assert equal $result "vouched"
}

export def "test slow fj-check-issue unvouched user blocked" [] {
  skip-without-token
  # Issue #5 is by evil_rowan (not vouched)
  let result = (
    fj-check-issue 5 -R $REPO -A $API_URL -P $PLATFORM --dry-run=true
  )
  assert equal $result "closed"
}

export def "test slow fj-check-issue unvouched allowed without require-vouch" [] {
  skip-without-token
  # Issue #5 by evil_rowan, require-vouch=false
  let result = (
    fj-check-issue 5
      -R $REPO
      -A $API_URL 
      -P $PLATFORM
      --require-vouch=false
      --dry-run=true
  )
  assert equal $result "allowed"
}

export def "test slow fj-check-issue auto-close dry-run" [] {
  skip-without-token
  let result = (
    fj-check-issue 5
      -R $REPO
      -A $API_URL 
      -P $PLATFORM
      --auto-close=true
      --dry-run=true
  )
  assert equal $result "closed"
}

export def "test slow fj-check-issue vouched contributor" [] {
  skip-without-token
  # Issue #3 is by rowansalt (vouched as rowansalt)
  let result = (
    fj-check-issue 3 -R $REPO -A $API_URL -P $PLATFORM --dry-run=true
  )
  assert equal $result "vouched"
}

export def "test slow fj-check-issue missing repo errors" [] {
  skip-without-token
  let result = (do {
    nu -c (
      'use vouch *; fj-check-issue 1 --dry-run=true'
    )
  } | complete)
  assert ($result.exit_code != 0)
}

# --- fj-manage-by-issue ---

export def "test slow fj-manage-by-issue non-matching comment" [] {
  skip-without-token
  # Issue #3, comment 12895194 body is a normal
  # reply, not a vouch/denounce keyword.
  let result = (
    fj-manage-by-issue 3 12895194
      -R $REPO
      -A $API_URL 
      -P $PLATFORM
      --dry-run=true
  )
  assert equal $result "unchanged"
}

export def "test slow fj-manage-by-issue missing repo errors" [] {
  skip-without-token
  let result = (do {
    nu -c (
      'use vouch *;'
      + ' fj-manage-by-issue 1 999 --dry-run=true'
    )
  } | complete)
  assert ($result.exit_code != 0)
}

# --- fj-check-pr with custom vouched-file ---

export def "test slow fj-check-pr custom vouched-file" [] {
  skip-without-token
  # Using a non-existent vouched file; RowanDavitt is
  # still a collaborator so result is vouched.
  let result = (
    fj-check-pr 1
      -R $REPO
      -A $API_URL 
      -P $PLATFORM
      --vouched-file "nonexistent/VOUCHED.td"
      --dry-run=true
  )
  assert equal $result "vouched"
}

# --- fj-check-issue with separate vouched-repo ---

export def "test slow fj-check-issue with vouched-repo" [] {
  skip-without-token
  # Use the same repo as vouched-repo; RowanDavitt is a
  # collaborator so result is vouched.
  let result = (
    fj-check-issue 6
      -R $REPO
      -A $API_URL 
      -P $PLATFORM
      --vouched-repo $REPO
      --dry-run=true
  )
  assert equal $result "vouched"
}

# --- can-manage ---

export def "test slow can-manage owner has access" [] {
  skip-without-token
  # RowanDavitt is the repo owner (admin)
  let result = (
    can-manage "RowanDavitt" $API_URL "RowanDavitt" "vouch" 
  )
  assert equal $result true
}

export def "test slow can-manage non-collaborator denied" [] {
  skip-without-token
  # evil_rowan is not a collaborator on RowanDavitt/vouch
  let result = (
    can-manage "evil_rowan" $API_URL  "RowanDavitt" "vouch" 
      --platform_url $PLATFORM
  )
  assert equal $result false
}

export def "test slow can-manage with restrictive roles" [] {
  skip-without-token
  # RowanDavitt is admin; restrict to only "maintain"
  # so admin should be denied
  let result = (
    can-manage "RowanDavitt" $API_URL "RowanDavitt" "vouch"
      --roles [maintain]
      --platform_url $PLATFORM
  )
  assert equal $result false
}

export def "test slow can-manage with matching role" [] {
  skip-without-token
  # RowanDavitt is admin; include "admin" in roles
  let result = (
    can-manage "RowanDavitt" $API_URL "RowanDavitt" "vouch"
      --roles [admin]
      --platform_url $PLATFORM
  )
  assert equal $result true
}

export def "test slow can-manage legacy-permissions override" [] {
  skip-without-token
  # With roles set (no legacy default) but
  # legacy-permissions explicitly including "admin"
  let result = (
    can-manage "RowanDavitt" $API_URL "RowanDavitt" "vouch"
      --roles [maintain]
      --legacy-permissions [admin]
      --platform_url $PLATFORM
  )
  assert equal $result true
}

export def "test slow can-manage empty legacy with roles" [] {
  skip-without-token
  # When roles is set, legacy perms default to [].
  # With non-matching roles and no legacy fallback,
  # access should be denied.
  let result = (
    can-manage "RowanDavitt" $API_URL "RowanDavitt" "vouch"
      --roles [triage]
      --platform_url $PLATFORM
  )
  assert equal $result false
}
