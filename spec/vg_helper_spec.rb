# frozen_string_literal: true

#require_relative "../vg_helper"
require "tmpdir"
require "fileutils"

RSpec.describe VGHelper do
  let(:tmpdir) do
    dir = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(dir)
    dir
  end

  let(:date_df) do
    Rover::DataFrame.new(
      {
        "datetime" => [
          "2025-01-01 10:00:00",
          "2025-01-02 10:00:00",
          "2025-01-01 10:00:00",
          "2025-01-02 10:00:00"
        ],
        "category1" => ["A", "A", "B", "B"],
        "category2" => ["Orange", "Orange", "Apple", "Apple"],
        "value" => [10.0, 12.0, 20.0, 18.0]
      }
    )
  end

  let(:nominal_df) do
    Rover::DataFrame.new(
      {
        "label" => ["Step_001", "Step_002", "Step_001", "Step_002"],
        "category1" => ["A", "A", "B", "B"],
        "category2" => ["Orange", "Orange", "Apple", "Apple"],
        "value" => [10.0, 12.0, 20.0, 18.0]
      }
    )
  end

  let(:date_df) do
     Rover::DataFrame.new(
        {
          "datetime" => [
            "2026-01-01 10:00:00",
            "2026-01-02 10:00:00",
            "2026-01-03 10:00:00",

            "2026-01-01 10:00:00",
            "2026-01-02 10:00:00",
            "2026-01-03 10:00:00",

            "2026-01-01 10:00:00",
            "2026-01-02 10:00:00",
            "2026-01-03 10:00:00",

            "2026-01-01 10:00:00",
            "2026-01-02 10:00:00",
            "2026-01-03 10:00:00"
          ],

          "category1" => [
            "A", "A", "A",
            "A", "A", "A",
            "B", "B", "B",
            "B", "B", "B"
          ],

          "category2" => [
            "Orange", "Orange", "Orange",
            "Apple", "Apple", "Apple",
            "Orange", "Orange", "Orange",
            "Apple", "Apple", "Apple"
          ],

          "value" => [
            10, 12, 14,
            15, 13, 18,
            20, 22, 21,
            25, 24, 28
          ]
        }
    )
  end

  let(:date_df2) do
    Rover::DataFrame.new(
        {
          "datetime" => [
            "2026-01-01 12:00:00",
            "2026-01-02 12:00:00",
            "2026-01-04 12:00:00",

            "2026-01-01 10:00:00",
            "2026-01-02 10:00:00",
            "2026-01-03 10:00:00"
          ],

          "volume" => [
            100, 180, 130,
            60,  90, 120
          ],

          "kind" => [
            "Sales", "Sales", "Sales",
            "Cost",  "Cost",  "Cost"
          ]
        }
    )
  end

  describe ".draw_xdate" do
    it "通常カテゴリでグラフを生成できる" do
      expect {
        described_class.draw_xdate(
          date_df,
          "datetime",
          "value",
          "category1"
        )
      }.not_to raise_error
    end
    
    it "xdate_test.html を出力できる" do
      df = Rover::DataFrame.new(
        {
          "datetime" => [
            "2025-01-01 10:00:00",
            "2025-01-02 10:00:00",
            "2025-01-07 10:00:00"
          ],
          "category1" => ["A", "A", "A"],
          "value" => [10.0, 12.0, 11.0]
        }
      )

      chart = VGHelper.draw_xdate(
        df,
        "datetime",
        "value",
        "category1"
      )
      p chart

      tmpdir = File.expand_path("../tmp", __dir__)
      FileUtils.mkdir_p(tmpdir)

      path = File.join(tmpdir, "xdate_test.html")

      puts "WRITE TO: #{path}"

      VGHelper.write_htmls(chart, path)

      expect(File.exist?(path)).to be true
      expect(File.size(path)).to be > 0
    end

    it "xdateで複数カテゴリ・水平垂直線・第2軸を含むグラフを生成できる" do

      chart = VGHelper.draw_xdate(
        date_df,
        "datetime",
        "value",
        ["category1", "category2"],

        df2: date_df2,
        x2_col: "datetime",
        y2_col: "volume",
        y2_category_col: "kind",

        horizontallines: [
          [16, "warning"],
          [23, "limit"]
        ],

        verticallines: [
          ["2026-01-02 13:00:00", "center"]
        ],

        verticalcolors: ["#ff0000"],

        time_mode: :exact,
        title: "Complex xdate test"
      )

      tmpdir = File.expand_path("../tmp", __dir__)
      FileUtils.mkdir_p(tmpdir)

      path = File.join(tmpdir, "xdate_complex_test.html")

      VGHelper.write_htmls(chart, path)

      expect(File.exist?(path)).to be true
      expect(File.size(path)).to be > 0

      puts "WRITE TO: #{path}"

    end

    it "xdateで複数カテゴリ・水平線・第2軸を含む、パラメータGUI非表示かつy2軸ラベル左のグラフを生成できる" do

      chart = VGHelper.draw_xdate(
        date_df,
        "datetime",
        "value",
        ["category1", "category2"],

        df2: date_df2,
        x2_col: "datetime",
        y2_col: "volume",
        y2_category_col: "kind",

        xslide: false,
        yslide: false,
        category_check: false,
        reverse_orient: true,

        horizontallines: [
          [16, "warning"],
          [23, "limit"]
        ],

        #time_mode: :exact,
        title: "Complex xdate test"
      )

      tmpdir = File.expand_path("../tmp", __dir__)
      FileUtils.mkdir_p(tmpdir)

      path = File.join(tmpdir, "xdate_complex_noparamgui_test.html")

      VGHelper.write_htmls(chart, path)

      expect(File.exist?(path)).to be true
      expect(File.size(path)).to be > 0

      puts "WRITE TO: #{path}"

    end
    
    it "第1軸と水平線のみで表示できる" do
      df = Rover::DataFrame.new(
        {
          "datetime" => [
            "2025-01-01 10:00:00",
            "2025-01-02 10:00:00",
            "2025-01-03 10:00:00",
            "2025-01-04 10:00:00"
          ],
          "category" => ["A", "A", "B", "B"],
          "value" => [10.0, 12.0, 8.0, 15.0]
        }
      )

      chart = VGHelper.draw_xdate(
        df,
        "datetime",
        "value",
        "category",
        horizontallines: [
          [11.0, "target"]
        ],
        horizontalcolors: ["red"]
      )

      path = File.join(tmpdir, "xdate_y1_horizontal.html")
      VGHelper.write_htmls(chart, path)

      expect(chart).not_to be_nil
      expect(File.exist?(path)).to be true
      expect(File.size(path)).to be > 0

      puts "WRITE TO: #{path}"
    end
  end

  describe ".draw_xnominal" do
    it "通常カテゴリでグラフを生成できる" do
      expect {
        described_class.draw_xnominal(
          nominal_df,
          "label",
          "value",
          "category1"
        )
      }.not_to raise_error
    end

    it "multicategory・水平垂直線・第2軸・brush集計を含むグラフを生成できる" do
      df = Rover::DataFrame.new(
        {
          "label" => [
            "Step_001", "Step_002", "Step_003",
            "Step_001", "Step_002", "Step_003",
            "Step_001", "Step_002", "Step_003",
            "Step_001", "Step_002", "Step_003"
          ],

          "category1" => [
            "A", "A", "A",
            "A", "A", "A",
            "B", "B", "B",
            "B", "B", "B"
          ],

          "category2" => [
            "Orange", "Orange", "Orange",
            "Apple", "Apple", "Apple",
            "Orange", "Orange", "Orange",
            "Apple", "Apple", "Apple"
          ],

          "value" => [
            10, 12, 14,
            15, 13, 18,
            20, 22, 21,
            25, 24, 28
          ]
        }
      )

      df2 = Rover::DataFrame.new(
        {
          "label" => [
            "Step_001", "Step_002", "Step_003",
            "Step_001", "Step_002", "Step_003"
          ],

          "volume" => [
            100, 180, 130,
             60,  90, 120
          ],

          "kind" => [
            "Sales", "Sales", "Sales",
            "Cost",  "Cost",  "Cost"
          ]
        }
      )

      chart = described_class.draw_xnominal(
        df,
        "label",
        "value",
        ["category1", "category2"],

        df2: df2,
        x2_col: "label",
        y2_col: "volume",
        y2_category_col: "kind",

        horizontallines: [
          [16, "warning", 0],
          [23, "limit", 1]
        ],

        verticallines: [
          ["Step_002", "center", 0]
        ],
        verticalcolors: ["#ff0000"],

        initialxpoints: 3,

        xslide: true,
        yslide: true,
        category_check: true,

        reverse_orient: false,

        title: "Complex nominal test"
      )

      tmpdir = File.expand_path("../tmp", __dir__)
      FileUtils.mkdir_p(tmpdir)

      path =
        File.join(
          tmpdir,
          "xnominal_complex_test.html"
        )

      described_class.write_htmls(
        chart,
        path
      )

      expect(File.exist?(path)).to be true
      expect(File.size(path)).to be > 0

      html = File.read(path)

      #
      # multicategory
      #
      expect(html).to include("A_Orange")
      expect(html).to include("A_Apple")
      expect(html).to include("B_Orange")
      expect(html).to include("B_Apple")

      #
      # horizontal lines
      #
      expect(html).to include("warning")
      expect(html).to include("limit")

      #
      # second axis
      #
      expect(html).to include("volume")

      #
      # second-axis categories
      #
      expect(html).to include("Sales")
      expect(html).to include("Cost")

      #
      # brush
      #
      expect(html).to include("brush")

      #
      # statistics
      #
      expect(html).to include("avg")
      expect(html).to include("std")
      expect(html).to include("max")
      expect(html).to include("min")
      expect(html).to include("n:")

      expect(html).to include("Step_001")
      expect(html).to include("Step_002")
      expect(html).to include("Step_003")
      
      puts "WRITE TO: #{path}"
    end
    
    it "第1軸と水平線のみで表示できる" do
      df = Rover::DataFrame.new(
        {
          "step" => [
            "STEP_001",
            "STEP_002",
            "STEP_003",
            "STEP_004"
          ],
          "category" => ["A", "A", "B", "B"],
          "value" => [10.0, 12.0, 8.0, 15.0]
        }
      )

      chart = VGHelper.draw_xnominal(
        df,
        "step",
        "value",
        "category",
        horizontallines: [
          [11.0, "target"]
        ],
        horizontalcolors: ["red"]
      )

      path = File.join(tmpdir, "xnominal_y1_horizontal.html")
      VGHelper.write_htmls(chart, path)

      expect(chart).not_to be_nil
      expect(File.exist?(path)).to be true
      expect(File.size(path)).to be > 0

      puts "WRITE TO: #{path}"
    end
  end
end