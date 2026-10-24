# Releasing VGHelper

## Current preview

The candidate version is `0.1.3.pre.1`. Preparing a package or running CI
does not publish it. There is no automatic RubyGems upload workflow.

## Build and verify

Use a Git checkout of the candidate branch. Before building, commit the
intended files: the gemspec determines package contents with `git ls-files`.

```sh
bundle install
bundle exec rspec
bundle exec rake build
bundle exec ruby spec/support/package_smoke.rb pkg/vg_helper-0.1.3.pre.1.gem
```

GitHub Actions also runs these checks, plus offline browser tests. Its
`vg-helper-gem` artifact contains the built `.gem` file (inside a ZIP).
The package smoke test verifies the packaged version and runtime files,
extracts the gem, and renders offline HTML using its packaged code/assets.

You can install that candidate on your own machine before publishing:

```sh
gem install --local pkg/vg_helper-0.1.3.pre.1.gem
```

If using a downloaded artifact, extract the ZIP and omit `pkg/` in that
command. Installing a local gem does not upload it to RubyGems.org.

## Publish the preview

Use a RubyGems.org account that owns `vg_helper`. After checking the
candidate and its GitHub Actions results, authenticate on your machine
and publish the exact tested package:

```sh
gem signin
gem push pkg/vg_helper-0.1.3.pre.1.gem --host https://rubygems.org
```

Complete any MFA prompt. When using a downloaded CI artifact, omit
`pkg/`. Keep the package unchanged between testing and pushing.

Verify installation from RubyGems.org with:

```sh
gem install vg_helper -v 0.1.3.pre.1
```

For Bundler users:

```ruby
gem "vg_helper", "0.1.3.pre.1"
```

Ordinary installs ignore prereleases unless explicitly requested. If a
published preview needs changes, use `0.1.3.pre.2`, then `0.1.3.pre.3`,
and so on. Published version numbers cannot be reused.

## Promote to a stable release

After real-data checks, update `lib/vg_helper/version.rb` and the local
gem entry in `Gemfile.lock` to `0.1.3`, finalize the changelog and README,
and rerun the same tests and package checks. Publish the newly built
stable package after review.
