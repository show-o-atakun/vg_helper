# frozen_string_literal: true

require "rubygems/package"
require "tmpdir"
require_relative "../../lib/vg_helper/version"

gem_path = ARGV.fetch(0)
package = Gem::Package.new(gem_path)
spec = package.spec
raise "Unexpected gem name: #{spec.name}" unless spec.name == "vg_helper"
raise "Package version does not match the checkout" unless spec.version.to_s == VgHelper::VERSION

required_files = %w[
  lib/vg_helper.rb
  lib/vg_helper/version.rb
  lib/vg_helper/assets/vega.min.js
  lib/vg_helper/assets/vega-lite.min.js
  lib/vg_helper/assets/vega-embed.min.js
  LICENSE.txt
  THIRD_PARTY_LICENSES.txt
  README.md
  CHANGELOG.md
]
missing = required_files - spec.files
raise "Missing packaged files: #{missing.join(', ')}" unless missing.empty?
raise "Development files leaked into gem" if spec.files.any? { |name| name.start_with?("spec/", ".github/", "tmp/") }

Dir.mktmpdir("vg-helper-package-") do |directory|
  package.extract_files(directory)
  packaged_code = File.join(directory, "lib/vg_helper.rb")
  require packaged_code
  raise "Packaged library was not loaded" unless $LOADED_FEATURES.include?(packaged_code)

  df = Rover::DataFrame.new({
    "x" => ["2026-01-01", "2026-01-02"],
    "value" => [10, 20], "category" => [1, 1]
  })
  charts = [:draw_xdate, :draw_xnominal].map do |helper|
    VGHelper.public_send(helper, df, "x", "value", "category", title: "パッケージ確認")
  end
  html = VGHelper.to_html(charts)
  raise "Invalid generated HTML" unless html.valid_encoding? && html.include?("パッケージ確認")
  raise "Unexpected external runtime" if html.match?(/<script\b[^>]*\bsrc=/i)
  raise "Missing export controls" unless html.scan('"export":true').length == 2
  raise "Missing runtime license notices" unless html.include?("University of Washington Interactive Data Lab")
end

puts "Package smoke passed: #{spec.name} #{spec.version} (prerelease: #{spec.version.prerelease?})"
