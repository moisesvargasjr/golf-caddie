# Releasing to TestFlight

Commits and merges to `main` no longer go to TestFlight. A build reaches
testers only when you push a release tag:

| Channel | Who gets it | How to cut it | Tag |
|---|---|---|---|
| **CI** (optional) | nobody, it just builds and runs tests | push a branch or open a PR | none |
| **Alpha** | just me (internal TestFlight group) | `scripts/release.sh alpha` | `alpha/1.1.0-3` |
| **Beta** | friends (external TestFlight group) | `scripts/release.sh beta` | `beta/1.1.0-1` |

Alpha can be cut from any pushed branch, so you can try a feature before it's
merged. Beta must be cut from a commit that's already on `main`.

## Day to day

```sh
scripts/release.sh alpha      # try the current pushed commit on my phone
scripts/release.sh beta       # ship the current main to friends
```

Starting a new version for friends:

```sh
scripts/release.sh bump minor   # 1.1.0 → 1.2.0 (or: patch, major, 1.2.0)
# commit, open a PR, merge
scripts/release.sh beta
```

## Versioning

- **Marketing version** (`CFBundleShortVersionString`, `MAJOR.MINOR.PATCH`) is
  what testers see. Bump **minor** for each beta round with new features and
  **patch** for a fix-only beta. Stay on `1.x` until App Store launch.
  Alphas use whatever version is in the tree, which is normally the next beta
  you're working toward.
- **Build number** (`CFBundleVersion`): Xcode Cloud overwrites it with its own
  increasing build number on every archive, so you don't need to bump it in
  `project.yml` for cloud builds. Only `scripts/release-testflight.sh`
  (local upload) uses the number in the repo; bump it there before a local
  upload so it's higher than the last uploaded build.
- TestFlight groups builds under their marketing version, so testers see
  "1.2.0 (57)" and can tell rounds apart.

## One-time App Store Connect / Xcode Cloud setup

Workflows and tester groups are configured in App Store Connect, not in this
repo. Edit workflows in Xcode (Report navigator → Cloud → Manage Workflows) or
in App Store Connect → the app → Xcode Cloud → Manage Workflows.

### 1. Stop the current workflow from shipping every push

The current workflow archives every push to `main` and sends the build to
TestFlight. Pick one:

- **Simplest:** turn it into the **CI** workflow: keep the Branch Changes /
  Pull Request start condition, replace the Archive action with **Test**, and
  delete the TestFlight post-action.
- Or disable or delete it if you don't need cloud CI.

### 2. Create TestFlight groups

In App Store Connect → the app → TestFlight:

- **Internal group "Alpha"**: add yourself. Internal testers must be users on
  your App Store Connect team. Leave **automatic distribution** on: only alpha
  builds will be sent to this group anyway.
- **External group "Friends"**: invite friends by email, or turn on a public
  link (you can cap how many people can join). External testers only need an
  Apple ID and the TestFlight app.
- On **any other internal group**, turn **automatic distribution off**.
  Otherwise every uploaded build gets pushed to that group, which is a likely
  source of the email flood.
- Fill in **Test Information** (beta description, feedback email). External
  testing requires it.

### 3. Alpha workflow

- **Start condition:** Tag Changes → Custom Tags → tag begins with `alpha/`.
  Remove any branch start condition.
- **Action:** Archive, iOS, deployment preparation **TestFlight (Internal
  Testing Only)**.
- **Post-action:** TestFlight Internal Testing → group **Alpha**.

### 4. Beta workflow

- **Start condition:** Tag Changes → Custom Tags → tag begins with `beta/`.
- **Action:** Archive, iOS, deployment preparation **TestFlight and App Store**.
- **Post-action:** TestFlight External Testing → group **Friends**.
- The first build of each new marketing version goes through Beta App Review
  (usually under a day). Later builds of the same version usually skip review.

### 5. Quiet the notifications

- **Xcode Cloud build emails:** in App Store Connect, open your profile's
  notification settings and limit Xcode Cloud emails to failures, or turn
  them off. Workflows can also have their own notification post-actions.
  Remove any you don't want.
- **TestFlight "new build" emails to testers:** with the setup above, these
  only go out when you tag. Testers can also turn off email for an app in the
  TestFlight app.
