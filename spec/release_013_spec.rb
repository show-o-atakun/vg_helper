# frozen_string_literal: true

require "tmpdir"

RSpec.describe "VGHelper 0.1.3" do
  [:draw_xdate, :draw_xnominal].each do |helper|
    context helper.to_s do
      let(:df) do
        Rover::DataFrame.new({
          "x" => ["2026-01-01", "2026-01-02", "2026-01-01", "2026-01-02"],
          "y" => [10, 20, 15, 25], "category" => [1, 1, 2, 2]
        })
      end
      let(:df2) do
        Rover::DataFrame.new({
          "x" => ["2026-01-01", "2026-01-02", "2026-01-01", "2026-01-02"],
          "y2" => [100, 200, 50, 75], "kind" => [3, 3, 4, 4]
        })
      end

      define_method(:draw) do |**options|
        VGHelper.public_send(helper, df, "x", "y", "category", **options)
      end

      def parsed(chart)
        JSON.parse(chart.to_json)
      end

      def main_layer(spec)
        spec.fetch("layer").find { |layer| layer.key?("selection") }
      end

      def statistics(spec)
        spec.fetch("layer").select { |layer| layer.dig("mark", "type") == "text" }
      end

      it "normalizes numeric categories in rows, domains and checkbox labels" do
        original = df.to_a
        spec = parsed(draw(categories: [1, 2]))
        expect(main_layer(spec).dig("encoding", "color", "scale", "domain")).to eq(["1", "2"])
        expect(spec.fetch("data").fetch("values").map { |r| r["category"] }.uniq).to eq(["1", "2"])
        expect(spec.fetch("params").select { |p| p["name"].start_with?("show_") }.map { |p| p.dig("bind", "name") }).to eq(["1", "2"])
        expect(df.to_a).to eq(original)
      end

      it "warns for NaN in both dataframes without changing data or dropping rows" do
        df["y"] = [10.0, Float::NAN, Float::NAN, 25.0]
        df2["y2"] = [100.0, Float::NAN, 50.0, 75.0]
        chart = nil
        expect { chart = draw(df2: df2, y2_col: "y2") }.to output(/df column "y" contains 2 NaN.*df2 column "y2" contains 1 NaN/m).to_stderr
        rows = parsed(chart).fetch("data").fetch("values")
        source = helper == :draw_xdate ? "_data_src" : "_src"
        main = rows.select { |r| r[source] == "main" }
        second = rows.select { |r| r[source] == "bar" }
        expect(main.length).to eq(4)
        expect(main.count { |r| r["y"].nil? }).to eq(2)
        expect(second.length).to eq(4)
        expect(second.count { |r| r["y2"].nil? }).to eq(1)
        expect(df["y"].to_a.count(&:nan?)).to eq(2)
        expect(df2["y2"].to_a.count(&:nan?)).to eq(1)
      end

      it "handles all-NaN measures and reports even unused NaN columns" do
        df["y"] = [Float::NAN] * 4
        df["unused"] = [1.0, Float::NAN, 2.0, 3.0]
        expect { parsed(draw) }.to output(/column "y" contains 4 NaN.*column "unused" contains 1 NaN/m).to_stderr
      end

      it "uses stacked totals for the first bar axis range and statistics" do
        spec = parsed(draw(markkind: :bar))
        expect(main_layer(spec).dig("encoding", "y", "stack")).to eq("zero")
        expect(spec.fetch("params").find { |p| p["name"] == "max_y" }.fetch("value")).to eq(45)
        totals = statistics(spec)[0].fetch("transform").find { |t| t["groupby"] }
        expect(totals.fetch("aggregate")[0]).to include("op" => "sum", "field" => "y")
      end

      it "keeps separate positive and negative stack bounds" do
        df["y"] = [10, -20, 15, -25]
        spec = parsed(draw(markkind: :bar))
        expect(spec.fetch("params").find { |p| p["name"] == "min_y" }.fetch("value")).to eq(-45)
        expect(spec.fetch("params").find { |p| p["name"] == "max_y" }.fetch("value")).to eq(25)
      end

      it "allows unstacked bars and keeps line statistics on observations" do
        [draw(markkind: :bar, stack: false), draw(markkind: :line)].each do |chart|
          spec = parsed(chart)
          expect(main_layer(spec).dig("encoding", "y", "stack")).to be_nil
          expect(statistics(spec)[0].fetch("transform").none? { |t| t["groupby"] }).to be true
        end
      end

      [:bar, :line, :line_dot, :point].each do |mark|
        it "supports #{mark} on the second axis with a fixed range" do
          original = df2.to_a
          spec = parsed(draw(df2: df2, y2_col: "y2", y2_category_col: "kind", markkind2: mark, miny2: 0, maxy2: 400))
          second = spec.fetch("layer")[0]
          expect(second.dig("mark", "type")).to eq(mark == :line_dot ? "line" : mark == :point ? "point" : mark.to_s)
          expect(second.dig("encoding", "y", "scale")).to include("domain" => [0, 400], "zero" => false, "nice" => false)
          expect(second.dig("encoding", "y", "stack")).to eq(mark == :bar ? "zero" : nil)
          totals = statistics(spec)[1].fetch("transform").any? { |t| t["groupby"] }
          expect(totals).to eq(mark == :bar)
          expect(df2.to_a).to eq(original)
        end
      end

      it "infers a missing second-axis limit from the displayed mark" do
        spec = parsed(draw(df2: df2, y2_col: "y2", y2_category_col: "kind", miny2: -10))
        expect(spec.fetch("layer")[0].dig("encoding", "y", "scale", "domain")).to eq([-10, 275])
        spec = parsed(draw(df2: df2, y2_col: "y2", markkind2: :line, maxy2: 300))
        expect(spec.fetch("layer")[0].dig("encoding", "y", "scale", "domain")).to eq([50, 300])
      end

      it "rejects reversed second-axis limits" do
        expect { draw(df2: df2, y2_col: "y2", miny2: 400, maxy2: 0) }.to raise_error(ArgumentError, /miny2/)
      end

      it "accepts custom secondary marks" do
        spec = parsed(draw(df2: df2, y2_col: "y2", markkind2: { "type" => "point", "size" => 80 }))
        expect(spec.fetch("layer")[0].fetch("mark")).to eq("type" => "point", "size" => 80)
      end

      it "returns editable standalone HTML and delegates file output to it" do
        chart = draw(title: "測定結果")
        html = VGHelper.to_html([chart, [chart]])
        expect(html).to include("<!doctype html>", "測定結果", "</html>")
        expect(html.scan('"export":true').length).to eq(2)
        expect(html).not_to match(/<script\b[^>]*\bsrc=/i)
        Dir.mktmpdir do |dir|
          path = File.join(dir, "chart.html")
          expect(VGHelper).to receive(:to_html).with(chart).and_return(html)
          VGHelper.write_htmls(chart, path)
          expect(File.read(path, encoding: "utf-8")).to eq(html)
        end
      end
    end
  end
end
