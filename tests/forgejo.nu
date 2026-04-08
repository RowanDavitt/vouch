use std/assert

use ../vouch/forgejo.nu [
  can-manage
  fj-check-issue
  fj-check-pr
  fj-manage-by-issue
]

const REPO = "RowanDavitt/vouch"
const API_URL = "https://codeberg.org/api/v1" 
const PLATFORM = "https://codeberg.org" 

export def "test slow fj-check-pr owner is vouched" [] {

  # PR #48 is by mitchellh (repo owner / collaborator)
  let result = (
    fj-check-pr 48 -R $REPO -A $API_URL -P $PLATFORM --dry-run=true
  )
  assert equal $result "vouched"
}

export def "test slow fj-check-pr vouched contributor" [] {

  # PR #42 is by meherhendi (in the vouched list)
  let result = (
    fj-check-pr 42 -R $REPO -A $API_URL -P $PLATFORM --dry-run=true
  )
  assert equal $result "vouched"
}

export def "test slow fj-check-pr unvouched user blocked" [] {
  # PR #25 is by cipz (not in the vouched list,
  # not a collaborator)
  let result = (
    fj-check-pr 25 -R $REPO -A $API_URL -P $PLATFORM --dry-run=true
  )
  assert equal $result "closed"
}

export def "test slow fj-check-pr unvouched allowed without require-vouch" [] {

  # PR #25 by cipz, with require-vouch=false
  let result = (
    fj-check-pr 25
      -R $REPO
      -A $API_URL
      -P $PLATFORM
      --require-vouch=false
      --dry-run=true
  )
  assert equal $result "allowed"
}

export def "test slow fj-check-pr auto-close dry-run" [] {

  # PR #25 by cipz, with auto-close + dry-run
  let result = (
    fj-check-pr 25
      -R $REPO
      -A $API_URL 
      -P $PLATFORM
      --auto-close=true
      --dry-run=true
  )
  assert equal $result "closed"
}

export def "test slow fj-check-pr bot is skipped" [] {
  # PR #27 is by dependabot[bot]
  let result = (
    fj-check-pr 27 -R $REPO -A $API_URL -P $PLATFORM --dry-run=true
  )
  assert equal $result "skipped"
}

export def "test slow fj-check-pr missing repo errors" [] {
  let result = (do {
    nu -c (
      'use vouch *; fj-check-pr 1 --dry-run=true'
    )
  } | complete)
  assert ($result.exit_code != 0)
}

# --- fj-check-issue ---

export def "test slow fj-check-issue owner is vouched" [] {
  # Issue #46 is by mitchellh (repo owner)
  let result = (
    fj-check-issue 46 -R $REPO -A $API_URL -P $PLATFORM --dry-run=true
  )
  assert equal $result "vouched"
}

export def "test slow fj-check-issue unvouched user blocked" [] {

  # Issue #45 is by rsromanowski (not vouched)
  let result = (
    fj-check-issue 45 -R $REPO -A $API_URL -P $PLATFORM --dry-run=true
  )
  assert equal $result "closed"
}

export def "test slow fj-check-issue unvouched allowed without require-vouch" [] {

  # Issue #45 by rsromanowski, require-vouch=false
  let result = (
    fj-check-issue 45
      -R $REPO
      -A $API_URL 
      -P $PLATFORM
      --require-vouch=false
      --dry-run=true
  )
  assert equal $result "allowed"
}

export def "test slow fj-check-issue auto-close dry-run" [] {

  let result = (
    fj-check-issue 45
      -R $REPO
      -A $API_URL 
      -P $PLATFORM
      --auto-close=true
      --dry-run=true
  )
  assert equal $result "closed"
}

export def "test slow fj-check-issue vouched contributor" [] {

  # Issue #41 is by DitherDude (vouched as ditherdude)
  let result = (
    fj-check-issue 41 -R $REPO -A $API_URL -P $PLATFORM --dry-run=true
  )
  assert equal $result "vouched"
}

export def "test slow fj-check-issue missing repo errors" [] {

  let result = (do {
    nu -c (
      'use vouch *; fj-check-issue 1 --dry-run=true'
    )
  } | complete)
  assert ($result.exit_code != 0)
}

# --- fj-manage-by-issue ---

export def "test slow fj-manage-by-issue non-matching comment" [] {

  # Issue #45, comment 3872422330 body is a normal
  # reply, not a vouch/denounce keyword.
  let result = (
    fj-manage-by-issue 45 3872422330
      -R $REPO
      -A $API_URL 
      -P $PLATFORM
      --dry-run=true
  )
  assert equal $result "unchanged"
}

export def "test slow fj-manage-by-issue missing repo errors" [] {

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

  # Using a non-existent vouched file; mitchellh is
  # still a collaborator so result is vouched.
  let result = (
    fj-check-pr 48
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

  # Use the same repo as vouched-repo; mitchellh is a
  # collaborator so result is vouched.
  let result = (
    fj-check-issue 46
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

  # mitchellh is the repo owner (admin)
  let result = (
    can-manage "mitchellh" "mitchellh" "vouch"
  )
  assert equal $result true
}

export def "test slow can-manage non-collaborator denied" [] {

  # cipz is not a collaborator on mitchellh/vouch
  let result = (
    can-manage "mitchellh-nope" "mitchellh" "vouch"
  )
  assert equal $result false
}

export def "test slow can-manage with restrictive roles" [] {

  # mitchellh is admin; restrict to only "maintain"
  # so admin should be denied
  let result = (
    can-manage "mitchellh" $API_URL "mitchellh" "vouch"
      --roles [maintain]
      --platform_url $PLATFORM
  )
  assert equal $result false
}

export def "test slow can-manage with matching role" [] {

  # mitchellh is admin; include "admin" in roles
  let result = (
    can-manage "mitchellh" $API_URL "mitchellh" "vouch"
      --roles [admin]
      --platform_url $PLATFORM
  )
  assert equal $result true
}

export def "test slow can-manage legacy-permissions override" [] {

  # With roles set (no legacy default) but
  # legacy-permissions explicitly including "admin"
  let result = (
    can-manage "mitchellh" $API_URL "mitchellh" "vouch"
      --roles [maintain]
      --legacy-permissions [admin]
      --platform_url $PLATFORM
  )
  assert equal $result true
}

export def "test slow can-manage empty legacy with roles" [] {

  # When roles is set, legacy perms default to [].
  # With non-matching roles and no legacy fallback,
  # access should be denied.
  let result = (
    can-manage "mitchellh" $API_URL "mitchellh" "vouch"
      --roles [triage]
      --platform_url $PLATFORM
  )
  assert equal $result false
}
