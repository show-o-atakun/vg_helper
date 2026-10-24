# frozen_string_literal: true

require "vg_helper"
require "fileutils"

directory = ARGV.fetch(0)
FileUtils.mkdir_p(directory)
fixtures = []

[:draw_xdate, :draw_xnominal].each do |helper|
  df = Rover::DataFrame.new({
    "x" => ["2026-01-01", "2026-01-02", "2026-01-01", "2026-01-02"],
    "y" => [10, 20, 15, 25], "category" => [1, 1, 2, 2]
  })
  df2 = Rover::DataFrame.new({
    "x" => ["2026-01-01", "2026-01-02", "2026-01-01", "2026-01-02"],
    "y2" => [100, 200, 50, 75], "kind" => [3, 3, 4, 4]
  })
  [:bar, :line, :line_dot, :point].each do |secondary_mark|
    chart = VGHelper.public_send(helper, df, "x", "y", "category",
      df2: df2, y2_col: "y2", y2_category_col: "kind",
      markkind: :bar, markkind2: secondary_mark, miny2: 0, maxy2: 400,
      categories: [1, 2], title: "測定結果 #{helper} #{secondary_mark}")
    name = "#{helper}_#{secondary_mark}"
    VGHelper.write_htmls(chart, File.join(directory, "#{name}.html"))
    fixtures << { name: name, stacked_secondary: secondary_mark == :bar, spec: JSON.parse(chart.to_json) }
  end
end

File.write(File.join(directory, "fixtures.json"), JSON.generate(fixtures), encoding: "utf-8")
