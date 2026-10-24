# frozen_string_literal: true

require "tmpdir"

RSpec.describe "Image export" do
  let(:df) do
    Rover::DataFrame.new(
      "x" => ["2026-01-01", "2026-01-02"],
      "value" => [10, 20],
      "category" => ["A", "A"]
    )
  end

  [:draw_xdate, :draw_xnominal].each do |helper|
    context helper.to_s do
      let(:chart) { VGHelper.public_send(helper, df, "x", "value", "category", title: "測定結果") }

      it "enables PNG and SVG export without source or editor actions" do
        options = JSON.parse(chart.to_json).fetch("usermeta").fetch("embedOptions")

        expect(options.fetch("actions")).to eq(
          "export" => true, "source" => false, "compiled" => false, "editor" => false
        )
        expect(options.fetch("scaleFactor")).to eq("png" => 2, "svg" => 1)
      end

      it "preserves export options in HTML and IRuby output" do
        [chart.to_html, chart.to_iruby.last].each do |html|
          expect(html).to include('"export":true', '"png":2', '"svg":1')
        end
      end

      it "writes exportable offline HTML with UTF-8 runtimes and Japanese text" do
        Dir.mktmpdir do |dir|
          path = File.join(dir, "chart.html")
          VGHelper.write_htmls([chart, [chart]], path)
          html = File.read(path, encoding: "utf-8")

          expect(html.valid_encoding?).to be true
          expect(html).to include("測定結果")
          expect(html.scan('"export":true').length).to eq(2)
          expect(html).not_to match(/<script\b[^>]*\bsrc=/i)

          %w[vega.min.js vega-lite.min.js vega-embed.min.js].each do |name|
            runtime = File.read(File.expand_path("../lib/vg_helper/assets/#{name}", __dir__), encoding: "utf-8")
            expect(html).to include(runtime)
          end
        end
      end
    end
  end
end
