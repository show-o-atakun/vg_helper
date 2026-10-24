require "vega"
require "rover"
require "json"

# パラメータを任意に足せる/変更できるようにするには？

# Use Rover::DataFrame, Not Daru
# Usage: VGHelper::draw_xdate(df, "datetime", "value", ["category1", "category2"])

# TODO:
# With a secondary y-axis, the horizontal-line layer creates another
# y-axis overlapping the main y-axis because y scales are independent.
# Currently both axes intentionally use the same style.
# Refactor main + horizontal layers into a nested layer in a future release.

module VGHelper

	# functionalize
	DStep = 86400000

	module_function
	
	def udate(*params)
		t = if params.length == 1 && params[0].is_a?(Time)
			params[0].utc	
		elsif params.length == 1 && params[0].respond_to?(:to_time)
			params[0].to_time.utc
		elsif params.length == 1 && params[0].is_a?(String)
			parts = params[0].split(/[\s\/\-T:]/).map(&:to_i)
			Time.local(*parts[0..5])
		else

			# Array ex: [2025,7,31,0,0,8] or [2025, 7, 1]
			Time.local(*params)
		end

		return (t.to_i * 1000).to_i
	end

	def msec_to_s(msec, mode = :day)
		return nil if msec.nil?
		t = Time.at(msec / 1000.0).getlocal

		case mode
		when :day
			t.strftime("%Y-%m-%dT00:00:00")
		when :exact
			t.strftime("%Y-%m-%dT%H:%M:%S")
		else
			raise ArgumentError, "unknown time_mode: #{mode}"
		end
	end

	def floor_day_msec(msec)
		return nil if msec.nil?
		t = Time.at(msec / 1000.0).getlocal
		Time.local(t.year, t.month, t.day).to_i * 1000
	end

	def mark_preset(kind)
		case kind
		when :line
			{
			type: "line",
			tooltip: true,
			clip: true
			}

		when :line_dot
			{
			type: "line",
			point: {
				filled: true,
				size: 40
			},
			tooltip: true,
			clip: true
			}

		when :small_dot, :point
			{
			type: "point",
			filled: true,
			size: 25,
			opacity: 0.75,
			tooltip: true,
			clip: true
			}

		when :large_dot
			{
			type: "point",
			filled: true,
			size: 100,
			opacity: 0.75,
			tooltip: true,
			clip: true
			}

		when :bar
			{
			type: "bar",
			opacity: 0.75,
			tooltip: true,
			clip: true
			}

		else
			raise ArgumentError,
			"unknown mark preset: #{kind.inspect}"
		end
	end

	# Keep the caller's dataframe and rows intact. JSON has no NaN value, so
	# only the generated chart data uses null in its place.
	def warn_nan(df, label)
		counts = Hash.new(0)
		df.to_a.each do |row|
			row.each { |column, value| counts[column] += 1 if nan_value?(value) }
		end
		counts.each do |column, count|
			warn "VGHelper: #{label} column #{column.to_s.inspect} contains #{count} NaN value(s); rendering as null (rows retained)."
		end
	end

	def nan_value?(value)
		value.respond_to?(:nan?) && value.nan?
	end

	def chart_row(row)
		row.to_h.transform_keys(&:to_s).transform_values { |value| nan_value?(value) ? nil : value }
	end

	def category_value(value)
		value.nil? || nan_value?(value) ? nil : value.to_s
	end

	def chart_mark(mark, default = :line_dot)
		case mark
		when nil then mark_preset(default)
		when Symbol then mark_preset(mark)
		when Hash then mark.transform_keys(&:to_sym)
		else raise ArgumentError, "markkind must be a Symbol or Hash"
		end
	end

	def stacked_bar?(mark, stack)
		stack && mark[:type].to_s == "bar"
	end

	def data_domain(rows, field, x_field, stacked: false, zero: false)
		return [0, 1] if rows.none? { |row| !row[field].nil? }
		values = if stacked
			rows.group_by { |row| row[x_field] }.values.flat_map do |group|
				numbers = group.map { |row| row[field] }.compact
				[numbers.select { |v| v < 0 }.sum, numbers.select { |v| v > 0 }.sum]
			end
		else
			rows.map { |row| row[field] }.compact
		end
		values << 0 if zero || stacked
		values.empty? ? [0, 1] : values.minmax
	end

	# Statistics must follow the displayed mark: stacked totals for bars,
	# individual observations for lines and points.
	def configure_statistics!(layer, field, x_field, stacked)
		transforms = layer[:transform]
		transforms.reject! { |item| item[:aggregate] && item[:groupby] }
		stats = transforms.find { |item| item[:aggregate] }
		if stacked
			index = transforms.index(stats)
			transforms.insert(index, { aggregate: [{ op: "sum", field: field, as: "_vg_stack_total" }], groupby: [x_field] })
		end
		stats[:aggregate].reject! { |item| ["xmin", "xmax"].include?(item[:as]) }
		stats[:aggregate].each do |item|
			item[:field] = stacked ? "_vg_stack_total" : field unless item[:op] == "count"
		end
	end

	def secondary_scale(rows, field, x_field, mark, miny2, maxy2)
		bounds = data_domain(rows, field, x_field, stacked: mark[:type].to_s == "bar", zero: mark[:type].to_s == "bar")
		domain = [miny2.nil? ? bounds[0] : miny2, maxy2.nil? ? bounds[1] : maxy2]
		raise ArgumentError, "miny2 must not exceed maxy2" if domain[0] > domain[1]
		{ domain: domain, zero: false, nice: false }
	end

	def draw_xdate(df, x_col, y_col, category_col,
				   df2: nil, x2_col: nil, y2_col: nil, y2_category_col: nil,
				   horizontallines: [], horizontalcolors: nil,
				   verticallines: [], verticalcolors: nil,
				   minxdefault: nil, maxxdefault: nil,
				   minx: nil, maxx: nil,
				   miny: nil, maxy: nil, miny2: nil, maxy2: nil,
				   markkind: nil, markkind2: nil, stack: true, colorset: nil,
				   xslide: true,
				   yslide: true,
				   category_check: true,
				   yrangechanger: "number", 
				   time_mode: :day,
				   reverse_orient: false,
				   width: 640, height: 360,
				   title: nil, categories: nil)

		x_col = x_col.to_s
		y_col = y_col.to_s
		warn_nan(df, "df")
		warn_nan(df2, "df2") if df2

		
		############################
		# Multi Category Rows Setting
		############################
		values1 = df.dup

		if category_col.is_a?(Array)
			values1["multicategory"] =
				values1[category_col].to_a.map { _1.values.join("_") }
			category_col = "multicategory"
		else
			category_col = category_col.to_s
		end
		############################
		# Default Settings
		############################
		
		values1[category_col] = values1[category_col].to_a.map { |v| category_value(v) }
		categories = (categories || values1[category_col].to_a).map { |v| category_value(v) }.compact.uniq

		#markkind ||= {
		#	type: "line",
		#	point: { filled: true, size: 40 },
		#	tooltip: true,
		#	clip: true
		#}

		markkind = chart_mark(markkind)
		markkind2 = markkind2.nil? ? mark_preset(:bar).merge(opacity: 0.55, size: 24) : chart_mark(markkind2, :bar)
		main_stack = stacked_bar?(markkind, stack)


		title ||= y_col
		
		colorset ||= (["#1f77b4", "#ff7f0e", "#2ca02c", "#d62728", "#9467bd",
		               "#8c564b", "#e377c2", "#7f7f7f", "#bcbd22", "#17becf",
					   "#393b79", "#637939", "#8c6d31", "#843c39", "#7b4173"] * 10)[0...(categories.length)]
		horizontalcolors ||= (["#0000ff", "#ff0000"] * 6)[0...(horizontallines.length)]
		# colorset += horizontalcolors
		verticalcolors ||= (["#0000ff", "#ff0000"] * 6)[0...(verticallines.length)]
		# colorset += verticalcolors

		x1_msec = values1[x_col].to_a.map { |v| v.nil? || nan_value?(v) ? nil : udate(v) }

		if time_mode == :day
			x1_msec.map! { |v| floor_day_msec(v) }
		end

		values1[x_col] = x1_msec
		select_cols1 = [x_col, y_col, category_col].uniq
		values1 = values1[select_cols1]
		values1["dummy"] = "none"

		v1_array = values1.to_a.map do |row|
			r = chart_row(row)
			r["_x_date_str"] = msec_to_s(r[x_col], time_mode)
			r["_data_src"] = "main"
			r
		end

		# df2の前処理
		v2_array = []
		x2_col = (x2_col || x_col).to_s
		y2_col = y2_col&.to_s
		y2_category_col = y2_category_col&.to_s
		
		x2_msec = []
		if df2 && y2_col
			v2 = df2.dup
			x2_msec = v2[x2_col].to_a.map { |v| v.nil? || nan_value?(v) ? nil : udate(v) }

			if time_mode == :day
				x2_msec.map! { |v| floor_day_msec(v) }
			end

			v2[x2_col] = x2_msec
			v2[y2_col] = v2[y2_col].to_a.map { |v| v.nil? ? nil : v.to_f }
			v2[y2_category_col] = v2[y2_category_col].to_a.map { |v| category_value(v) } if y2_category_col

			select_cols2 = [x2_col, y2_col]
			select_cols2 << y2_category_col if y2_category_col
			v2 = v2[select_cols2.uniq]

			raw_v2 = v2.is_a?(Rover::DataFrame) ? v2.to_a : v2
			v2_array = raw_v2.map do |row|
				r = chart_row(row)
				r["_x_date_str"] = msec_to_s(r[x2_col], time_mode)
				r["_data_src"] = "bar"
				r
			end
		end

		############################
		# Range Settings
		############################

		# x range

		all_x = (x1_msec + x2_msec).compact
		raise ArgumentError, "no valid x values to draw" if all_x.empty?
		all_x_min, all_x_max = all_x.minmax

		if time_mode == :day
			all_x_min = floor_day_msec(all_x_min)
			all_x_max = floor_day_msec(all_x_max)
		end

		minxdefault ||= all_x_min
		maxxdefault ||= all_x_max

		minx ||= all_x_min
		maxx ||= all_x_max

		# y range

		bounds = data_domain(v1_array, y_col, "_x_date_str", stacked: main_stack, zero: markkind[:type].to_s == "bar")
		miny ||= bounds[0]
		maxy ||= bounds[1]
		
		if !horizontallines.empty?
			horizmin = horizontallines.map { _1[0] }.min
			horizmax = horizontallines.map { _1[0] }.max
			miny = [horizmin, miny].min
			maxy = [horizmax, maxy].max
		end

		# Array 指定時
		minxdefault = udate(*minxdefault) if minxdefault.is_a? Array
		maxxdefault = udate(*maxxdefault) if maxxdefault.is_a? Array
		minx = udate(*minx) if minx.is_a? Array
		maxx = udate(*maxx) if maxx.is_a? Array
		

		# 垂直線データ
		vertical_array = verticallines.map do |vv|
			x_msec = udate(vv[0])
			x_msec = floor_day_msec(x_msec) if time_mode == :day

			{
				"_x_date_str" => msec_to_s(x_msec, time_mode),
				"_vertical_name" => vv[1].to_s,
				"_vertical_dash" => vv[2] || 0,
				"_data_src" => "vertical"
			}
		end

		all_values = v1_array + v2_array + vertical_array

		# X軸
		x_encoding = {
			field: "_x_date_str",
			type: "temporal",
			scale: {
				domain: [
				{ expr: "min_x" },
				{ expr: "max_x" }
				]
			},
			axis: {
				format: "%Y/%m/%d",
				titleFontSize: 16,
				labelFontSize: 14
			}
		}

		#if time_mode == :day
		#	x_encoding[:timeUnit] = "utcyearmonthdate"
		#end

		main_y_axis = {
			orient: reverse_orient ? :right : :left,
			titleFontSize: 16,
			labelFontSize: 14
		}

		# 水平線データの構築
		horiz_layer = []
		if horizontallines && !horizontallines.empty?
			x_vals_for_horiz = (x1_msec + [minxdefault, maxxdefault]).compact.uniq.sort
			
			horizontallines.each do |hv|
				horiz_rows = x_vals_for_horiz.map do |x_val|
					{
						x_col => x_val,
						y_col => hv[0],
						category_col => hv[1],
						"dummy" => "horiz",
						"_x_date_str" => msec_to_s(x_val, time_mode),
						"_data_src" => "main"
					}
				end
				all_values.concat(horiz_rows)
			end

			horiz_layer = [{
				mark: { type: "line", point: false, tooltip: false, clip: true },
				transform: [
					{ filter: "datum['_data_src'] == 'main' && datum.dummy == 'horiz'" }
				],
				encoding: {
					x: x_encoding,
					y: { 
						field: y_col,
						type: "quantitative",
						scale: { domain: [{expr: "min_y"}, {expr: "max_y"}] },
						axis: main_y_axis 
						#axis: nil
					},
					color: {
						field: category_col,
						type: "nominal",
						scale: {
							domain: horizontallines.map { _1[1] },
					 		range: horizontalcolors
						}
					}
				},
				
			}]
		end

		vertical_layer = []
		if verticallines && !verticallines.empty?
			# 垂直線レイヤ
			vertical_layer += [{
				mark: {
					type: "rule",
					strokeWidth: 2,
					clip: true
				},
				transform: [
					{ filter: "datum['_data_src'] == 'vertical'" }
				],
				encoding: {
					x: x_encoding,
					color: {
						field: "_vertical_name",
						type: "nominal",
						scale: {
							domain: verticallines.map { _1[1].to_s },
							range: verticalcolors
						}
					},
					strokeDash: {
						field: "_vertical_dash",
						type: "nominal",
						legend: false
					}
				}
				}]
		end

		############################
		# filtering parameter settings
		############################

		params = []

		if xslide
			params += [
				{
				name: "min_x",
				value: minxdefault,
				bind: {
					input: "range",
					min: minx,
					max: maxx,
					step: DStep
				}
				},
				{
				name: "max_x",
				value: maxxdefault,
				bind: {
					input: "range",
					min: minx,
					max: maxx,
					step: DStep
				}
				}
			]
		else
			params += [
				{ name: "min_x", value: minxdefault },
				{ name: "max_x", value: maxxdefault }
			]
		end

		params += [
		  {
			name: "min_x_label",
		  	expr: "timeFormat(min_x, '%Y/%m/%d', 'utc')"
		  },
		  {
			name: "max_x_label",
		  	expr: "timeFormat(max_x, '%Y/%m/%d', 'utc')"
		  }
		]

		if yslide
			params +=  [
				{
					name: "min_y",
					value: miny,
					bind: {
					input: yrangechanger,  # yrangechanger: "range" も可能
					min: miny,
					max: maxy
					}
				},
				{
					name: "max_y",
					value: maxy,
					bind: {
					input: yrangechanger,
					min: miny,
					max: maxy
					}
				}		  
			]
		else
			params += [
				{ name: "min_y", value: miny },
				{ name: "max_y", value: maxy }
			]
		end
		
		categ_params = categories.map.with_index do |c, i|
			ctp = {
				name: "show_#{i}",
				value: true
			}

			if category_check
				ctp[:bind] = {
				input: "checkbox",
				name: c
				}
			end

			ctp
		end

		params += categ_params
		
		categ_transforms = categories.map.with_index {|c, i|
			 "(show_#{i} && datum[#{category_col.to_s.to_json}] == #{c.to_s.to_json})" }
		.join(" || ")
		categ_transforms = "false" if categ_transforms.empty?
		
		# 第二縦軸
		bar_layer = []
		if !v2_array.empty? 
			bar_encoding = {
				x: {
					field: "_x_date_str",
					type: "temporal",
					scale: {
						domain: [
						{ expr: "min_x" },
						{ expr: "max_x" }
						],
						padding: 24
					},
					#axis: nil
				},
				y: {
					field: y2_col,
					type: "quantitative", 
					axis: {
						orient: reverse_orient ? :left : :right,
						title: y2_col,
						titleFontSize: 16,
						labelFontSize: 14
					}
				}
			}

			if y2_category_col
				bar_encoding[:color] = {
					field: y2_category_col,
					type: "nominal",
					legend: { title: y2_category_col }
				}
			end

			bar_layer = [{
				mark: markkind2,
				transform: [
					{ filter: "datum['_data_src'] == 'bar'" }
				],
				encoding: bar_encoding
			}]
		end

		# メインレイヤ
		main_layer = [{
			transform: [
				{ filter: "datum['_data_src'] == 'main' && datum.dummy == 'none'" },
				{ filter: categ_transforms }
			],
			selection: {
				brush: {
					type: "interval",
					encodings: ["x"],
					mark: {fill: "#dddddd", fillOpacity: 0.35 }
				}
			},
			mark: { **markkind },
			encoding: {
				x: x_encoding,
				y: {
					field: y_col,
					type: "quantitative",
					title: y_col,
					axis: main_y_axis,
					# axis: {
					#	orient: reverse_orient ? :right : :left,
					#	titleFontSize: 16,
					#	labelFontSize: 14
					#},
					scale: { domain: [{expr: "min_y"}, {expr: "max_y"}] }
				},
				color: {
					field: category_col,
					type: "nominal",
					scale: { domain: categories, range: colorset }
				}
			}
		}]

		# 情報表示レイヤ
		info_layer1 = [{
			transform: [
				{
				filter:
					"datum['#{x_col}'] >= min_x && datum['#{x_col}'] <= max_x"
				},
				{
				filter:
					"datum['_data_src'] == 'main' && datum.dummy == 'none'"
				},
				{
				filter: categ_transforms
				},
				{
				filter: { param: "brush" }
				},
				{
				aggregate: [
					{ op: "mean",  field: y_col, as: "avg" },
					{ op: "stdev", field: y_col, as: "std" },
					{ op: "max",   field: y_col, as: "max" },
					{ op: "min",   field: y_col, as: "min" },
					{ op: "count", as: "n" },

					{ op: "min", field: x_col, as: "xmin" },
					{ op: "max", field: x_col, as: "xmax" }
				]
				},
				{
				calculate:
					"'#{y_col}  n: ' + format(datum.n, 'd')" \
					" + '  avg: ' + format(datum.avg, '.2f')" \
					" + '  std: ' + format(datum.std, '.2f')" \
					" + '  max: ' + format(datum.max, '.2f')" \
					" + '  min: ' + format(datum.min, '.2f')",
				as: "label"
				}
			],

			mark: {
				type: "text",
				fontSize: 13,
				align: "left"
			},

			encoding: {
				text: { field: "label" },
				x: { value: 10 },
				y: { value: 10 }
			}
		}]

		info_layer2 = []

		unless v2_array.empty?
			info_layer2 = [{
				transform: [
				{
					filter:
					"datum['#{x2_col}'] >= min_x && datum['#{x2_col}'] <= max_x"
				},

				{
					filter:
					"datum['_data_src'] == 'bar'"
				},

				{
					filter: {
					param: "brush"
					}
				},

				# まず同じx位置の棒を合計
				{
					aggregate: [
					{
						op: "sum",
						field: y2_col,
						as: "stack_total"
					}
					],
					groupby: [
						#x2_col
						"_x_date_str"
					]
				},

				# その積み上げ合計群で統計
				{
					aggregate: [
					{
						op: "mean",
						field: "stack_total",
						as: "avg"
					},
					{
						op: "stdev",
						field: "stack_total",
						as: "std"
					},
					{
						op: "max",
						field: "stack_total",
						as: "max"
					},
					{
						op: "min",
						field: "stack_total",
						as: "min"
					},
					{
						op: "count",
						as: "n"
					}
					]
				},

				{
					calculate:
					"'#{y2_col}  n: ' + format(datum.n, 'd')" \
					" + '  avg: ' + format(datum.avg, '.2f')" \
					" + '  std: ' + format(datum.std, '.2f')" \
					" + '  max: ' + format(datum.max, '.2f')" \
					" + '  min: ' + format(datum.min, '.2f')",
					as: "label"
				}
				],

				mark: {
				type: "text",
				fontSize: 13,
				align: "left"
				},

				encoding: {
				text: {
					field: "label"
				},

				x: {
					value: 10
				},

				y: {
					value: 28
				}
				}
			}]
		end

		layers = bar_layer + horiz_layer + vertical_layer + main_layer + info_layer1 + info_layer2
		main_layer[0][:encoding][:y][:stack] = main_stack ? "zero" : nil if markkind[:type].to_s == "bar"
		configure_statistics!(info_layer1[0], y_col, "_x_date_str", main_stack)
		unless bar_layer.empty?
			bar_layer[0][:encoding][:y][:scale] = secondary_scale(v2_array, y2_col, "_x_date_str", markkind2, miny2, maxy2)
			bar_layer[0][:encoding][:y][:stack] = "zero" if markkind2[:type].to_s == "bar"
			configure_statistics!(info_layer2[0], y2_col, "_x_date_str", markkind2[:type].to_s == "bar")
		end

		builder = Vega.lite
			.title(title)
			.data(values: all_values)
			.params(params)
			.layer(layers)
			.width(width)
			.height(height)

		resolve_scale = {
			color: "independent",
			x: "shared"
			}

		resolve_scale[:y] = "independent" unless v2_array.empty?

		builder = builder.resolve(
			scale: resolve_scale,
			axis: { x: "shared" }
			)

		builder.embed_options(
			actions: { export: true, source: false, compiled: false, editor: false },
			scaleFactor: { png: 2, svg: 1 }
		)
		
	end
	
	def draw_xnominal(
		df, x_col, y_col, category_col,
		df2: nil, x2_col: nil, y2_col: nil, y2_category_col: nil,
		categories: nil,
		miny: nil, maxy: nil,
		miny2: nil, maxy2: nil,
		minydefault: nil, maxydefault: nil,
		initialxpoints: 300,
		markkind: nil, markkind2: nil, stack: true,
		colorset: nil,
		yrangechanger: "number",
		horizontallines: [],
		horizontalcolors: nil,
		verticallines: [],
    	verticalcolors: nil,
		width: 640,
		height: 360,
		title: nil,
		category_check: true,
		xslide: true,
		yslide: true,
		reverse_orient: false
		)

		############################
		# Column settings
		############################
		warn_nan(df, "df")
		warn_nan(df2, "df2") if df2

		x_col_str =
			x_col.is_a?(Array) ? "multix" : x_col.to_s

		y_col_str = y_col.to_s

		category_col_str =
			category_col.is_a?(Array) ? "multicategory" : category_col.to_s

		x2_source = x2_col || x_col

		x2_col_str =
			x2_source.is_a?(Array) ? "multix2" : x2_source.to_s

		y2_col_str = y2_col&.to_s

		y2_category_col_str =
			if y2_category_col.is_a?(Array)
			"multicategory2"
			else
			y2_category_col&.to_s
			end

		title ||= y_col_str

		############################
		# Mark settings
		############################

		# markkind = {
		#	type: "line",
		#	tooltip: true,
		#	point: {
		#	filled: false,
		#	size: 20
		#	},
		#	clip: true
		# }.merge(markkind || {})

		markkind = chart_mark(markkind)
		markkind2 = markkind2.nil? ? mark_preset(:bar).merge(opacity: 0.55, size: 24) : chart_mark(markkind2, :bar)
		main_stack = stacked_bar?(markkind, stack)

		############################
		# Main dataframe
		############################

		dfdup = df.dup

		if x_col.is_a?(Array)
			dfdup["multix"] =
			dfdup[x_col].to_a.map { _1.values.join("_") }
		end

		if category_col.is_a?(Array)
			dfdup["multicategory"] =
			dfdup[category_col].to_a.map { _1.values.join("_") }
		end

		dfdup[category_col_str] = dfdup[category_col_str].to_a.map { |v| category_value(v) }
		categories = (categories || dfdup[category_col_str].to_a).map { |v| category_value(v) }.compact.uniq

		############################
		# Second dataframe
		############################

		df2dup = nil

		if df2 && y2_col_str
			df2dup = df2.dup

			if x2_source.is_a?(Array)
			df2dup["multix2"] =
				df2dup[x2_source].to_a.map { _1.values.join("_") }
			end

			if y2_category_col.is_a?(Array)
			df2dup["multicategory2"] =
				df2dup[y2_category_col].to_a.map { _1.values.join("_") }
			end
			if y2_category_col_str
				df2dup[y2_category_col_str] = df2dup[y2_category_col_str].to_a.map { |v| category_value(v) }
			end
		end

		############################
		# X values / ordering
		############################

		x_all =
			dfdup[x_col_str]
			.to_a
			.map(&:to_s)

		if df2dup
			x_all +=
			df2dup[x2_col_str]
				.to_a
				.map(&:to_s)
		end

		# 元データの出現順を保持
		xcs = x_all.uniq

		xcsh =
			xcs.each_with_index.to_h

		############################
		# Main data
		############################

		v1_array =
			dfdup.to_a.map do |row|
			r = chart_row(row)

			x_value =
				r[x_col_str].to_s

			r["_x_value"] = x_value
			r["_order"] = xcsh[x_value]
			r["_src"] = "main"

			r
			end

		############################
		# Second-axis data
		############################

		v2_array = []

		if df2dup
			v2_array =
			df2dup.to_a.map do |row|
				r = chart_row(row)

				x_value =
				r[x2_col_str].to_s

				r["_x_value"] = x_value
				r[y2_col_str] =
				r[y2_col_str].nil? ? nil : r[y2_col_str].to_f

				r["_order"] =
				xcsh[x_value]

				r["_src"] = "bar"

				r
			end
		end

		############################
		# Horizontal-line data
		############################

		horiz_array = []

		unless horizontallines.empty?
			horizontallines.each do |hv|
				xcs.each do |x_value|
					horiz_array << {
					"_x_value" => x_value,
					y_col_str => hv[0],
					category_col_str => hv[1].to_s,
					"_order" => xcsh[x_value],
					"_dummy2" => hv[2] || 0,
					"_src" => "horiz"
					}
				end
			end
		end

		############################
		# Vertical-line data
		############################

		vertical_array = verticallines.map do |vv|
			{
				"_x_value" => vv[0].to_s,
				"_vertical_name" => vv[1].to_s,
				"_vertical_dash" => vv[2] || 0,
				"_src" => "vertical"
			}
		end

		############################
		# All data
		############################

		all_data =
			v1_array +
			horiz_array +
			vertical_array +
			v2_array

		############################
		# Y range
		############################

		bounds = data_domain(v1_array, y_col_str, "_x_value", stacked: main_stack, zero: markkind[:type].to_s == "bar")
		miny ||= bounds[0]
		maxy ||= bounds[1]

		unless horizontallines.empty?
			horiz_min =
			horizontallines.map { _1[0] }.min

			horiz_max =
			horizontallines.map { _1[0] }.max

			miny =
			[miny, horiz_min].min

			maxy =
			[maxy, horiz_max].max
		end

		minydefault ||= miny
		maxydefault ||= maxy

		############################
		# Colors
		############################

		colorset ||= (
			[
			"#1f77b4",
			"#ff7f0e",
			"#2ca02c",
			"#d62728",
			"#9467bd",
			"#8c564b",
			"#e377c2",
			"#7f7f7f",
			"#bcbd22",
			"#17becf",
			"#393b79",
			"#637939",
			"#8c6d31",
			"#843c39",
			"#7b4173"
			] * 10
		)[0...categories.length]

		horizontalcolors ||= (
			["#0000ff", "#ff0000"] * 10
		)[0...horizontallines.length]

		verticalcolors ||= (["#0000ff", "#ff0000"] * 6)[0...(verticallines.length)]

		############################
		# X slider
		############################

		max_order =
			xcs.length - 1

		default_start =
			[
			max_order -
				(initialxpoints - 1),
			0
			].max

		params = []

		if xslide
			params += [
			{
				name: "start",
				value: default_start,
				bind: {
				input: "range",
				min: 0,
				max: max_order,
				step: 1
				}
			},
			{
				name: "end",
				value: max_order,
				bind: {
				input: "range",
				min: 0,
				max: max_order,
				step: 1
				}
			}
			]
		end

		xslide_transform =
			if xslide
				[
					{
					filter:
						"datum._order >= start && datum._order <= end"
					}
				]
			else
				[]
			end

		############################
		# Y slider
		############################

		if yslide
			params += [
				{
					name: "min_y",
					value: minydefault,
					bind: {
					input: yrangechanger,
					min: miny,
					max: maxy
					}
				},
				{
					name: "max_y",
					value: maxydefault,
					bind: {
					input: yrangechanger,
					min: miny,
					max: maxy
					}
				}
			]

			ydomain = [
				{ expr: "min_y" },
				{ expr: "max_y" }
			]
		else
			ydomain = [
				minydefault,
				maxydefault
			]
		end

		############################
		# Category checkbox
		############################

		category_transforms = []

		if category_check
			category_params =
			categories.map.with_index do |c, i|
				{
				name: "show_#{i}",
				value: true,
				bind: {
					input: "checkbox",
					name: c
				}
				}
			end

			params += category_params

			categ_filter_str =
			categories.map.with_index do |c, i|
				"(show_#{i} && datum[#{category_col_str.to_s.to_json}] == #{c.to_s.to_json})"
			end.join(" || ")
			categ_filter_str = "false" if categ_filter_str.empty?

			category_transforms = [
			{
				filter:
				categ_filter_str
			}
			]
		end

		############################
		# Y Axises
		############################
		
		main_y_axis = {
			orient: reverse_orient ? :right : :left,
			titleFontSize: 16,
			labelFontSize: 14
		}

		############################
		# Common X encoding
		############################

		x_encoding = {
			field: "_x_value",
			type: "nominal",

			# ここ重要。
			# Step_001 → Step_002 → ... の順序を保持。
			sort: xcs,

			scale: {
			type: "band"
			},

			axis: {
			title: x_col_str,
			labelOverlap: "parity",
			titleFontSize: 16,
			labelFontSize: 14
			}
		}

		############################
		# Layers
		############################

		layers = []

		############################
		# Second-axis bars
		############################

		unless v2_array.empty?
			bar_encoding = {
			y: {
				field: y2_col_str,
				type: "quantitative",

				axis: {
				orient:
					reverse_orient ? :left : :right,

				title:
					y2_col_str,

				titleFontSize: 16,
				labelFontSize: 14
				}
			}
			}

			if y2_category_col_str
			bar_encoding[:color] = {
				field:
				y2_category_col_str,

				type:
				"nominal",

				legend: {
				title:
					y2_category_col_str
				}
			}
			end

			layers << {
			mark: markkind2,

			transform:
				xslide_transform +
				[
				{
					filter:
					"datum._src == 'bar'"
				}
				],

			encoding:
				bar_encoding
			}
		end

		############################
		# Horizontal lines
		############################

		unless horizontallines.empty?
			layers << {
			mark: {
				type: "line",
				point: false,
				tooltip: false,
				clip: true
			},

			transform:
				xslide_transform +
				[
				{
					filter:
					"datum._src == 'horiz'"
				}
				],

			encoding: {
				y: {
					field: y_col_str,
					type: "quantitative",
					scale: { domain: ydomain },
					axis: main_y_axis
					#axis: nil 
				},
				color: {
				field:
					category_col_str,

				type:
					"nominal",

				scale: {
					domain:
					horizontallines.map {
						_1[1].to_s
					},

					range:
					horizontalcolors
				}
				},

				strokeDash: {
				field:
					"_dummy2",

				type:
					"nominal",

				title:
					"",

				legend:
					false
				}
			}
			}
		end

		############################
		# Vertical lines
		############################

		unless verticallines.empty?
			layers << {
				mark: {
					type: "rule",
  					strokeWidth: 2,
					clip: true
				},
				transform: [
					{ filter: "datum['_src'] == 'vertical'" }
				],
				encoding: {
					x: x_encoding,
					color: {
						field: "_vertical_name",
						type: "nominal",
						scale: {
							domain: verticallines.map { _1[1].to_s },
							range: verticalcolors
						}
					},
					strokeDash: {
						field: "_vertical_dash",
						type: "nominal",
						legend: false
					}
				}
			}
		end

		############################
		# Main line
		############################

		layers << {
			mark:
			markkind,

			transform:
			xslide_transform +
			[
				{
				filter:
					"datum._src == 'main'"
				}
			] +
			category_transforms,

			selection: {
			brush: {
				type:
				"interval",

				encodings:
				["x"],

				mark: {
				fill:
					"#dddddd",

				fillOpacity:
					0.35
				}
			}
			},

			encoding: {
			y: {
				field:
				y_col_str,

				type: "quantitative",
				# axis: {
				#	orient: reverse_orient ? :right : :left,
				#	title: y_col_str,
				#	titleFontSize: 16,
				#	labelFontSize: 14,
				# },
				axis: main_y_axis, 
				scale: { domain: ydomain }
			},

			color: {
				field:
				category_col_str,

				type:
				"nominal",

				scale: {
				domain:
					categories,

				range:
					colorset
				}
			}
			}
		}

		############################
		# Main-axis statistics
		############################

		layers << {
			transform:
			xslide_transform +
			[
				{
				filter:
					"datum._src == 'main'"
				}
			] +
			category_transforms +
			[
				{
				filter: {
					param:
					"brush"
				}
				},

				{
				aggregate: [
					{
					op: "mean",
					field: y_col_str,
					as: "avg"
					},
					{
					op: "stdev",
					field: y_col_str,
					as: "std"
					},
					{
					op: "max",
					field: y_col_str,
					as: "max"
					},
					{
					op: "min",
					field: y_col_str,
					as: "min"
					},
					{
					op: "count",
					as: "n"
					}
				]
				},

				{
				calculate:
					"'#{y_col_str}  n: ' + format(datum.n, 'd')" \
					" + '  avg: ' + format(datum.avg, '.2f')" \
					" + '  std: ' + format(datum.std, '.2f')" \
					" + '  max: ' + format(datum.max, '.2f')" \
					" + '  min: ' + format(datum.min, '.2f')",

				as:
					"label"
				}
			],

			mark: {
			type:
				"text",

			fontSize:
				13,

			align:
				"left"
			},

			encoding: {
			text: {
				field:
				"label"
			},

			x: {
				value:
				10
			},

			y: {
				value:
				10
			}
			}
		}

		############################
		# Second-axis statistics
		############################

		unless v2_array.empty?
			layers << {
				transform:
				xslide_transform +
				[
					{
					filter:
						"datum._src == 'bar'"
					},

					{
					filter: {
						param: "brush"
					}
					},

					# --------------------------------
					# まず各Xについて積み上げ棒の高さを求める
					# --------------------------------
					{
					aggregate: [
						{
						op: "sum",
						field: y2_col_str,
						as: "stack_total"
						}
					],
					groupby: [
						"_x_value"
					]
					},

					# --------------------------------
					# stack_total を一つの観測値として統計
					# --------------------------------
					{
					aggregate: [
						{
						op: "mean",
						field: "stack_total",
						as: "avg"
						},
						{
						op: "stdev",
						field: "stack_total",
						as: "std"
						},
						{
						op: "max",
						field: "stack_total",
						as: "max"
						},
						{
						op: "min",
						field: "stack_total",
						as: "min"
						},
						{
						op: "count",
						as: "n"
						}
					]
					},

					{
					calculate:
						"'#{y2_col_str}  n: ' + format(datum.n, 'd')" \
						" + '  avg: ' + format(datum.avg, '.2f')" \
						" + '  std: ' + format(datum.std, '.2f')" \
						" + '  max: ' + format(datum.max, '.2f')" \
						" + '  min: ' + format(datum.min, '.2f')",

					as: "label"
					}
				],

				mark: {
				type: "text",
				fontSize: 13,
				align: "left"
				},

				encoding: {
				text: {
					field: "label"
				},

				x: {
					value: 10
				},

				y: {
					value: 28
				}
				}
			}
			end

		############################
		# Build
		############################
		main_layer = layers.find { |layer| layer[:selection] }
		main_layer[:encoding][:y][:stack] = main_stack ? "zero" : nil if markkind[:type].to_s == "bar"
		info_layers = layers.select { |layer| layer.dig(:mark, :type) == "text" }
		configure_statistics!(info_layers[0], y_col_str, "_x_value", main_stack)
		unless v2_array.empty?
			secondary_layer = layers[0]
			secondary_layer[:encoding][:y][:scale] = secondary_scale(v2_array, y2_col_str, "_x_value", markkind2, miny2, maxy2)
			secondary_layer[:encoding][:y][:stack] = "zero" if markkind2[:type].to_s == "bar"
			configure_statistics!(info_layers[1], y2_col_str, "_x_value", markkind2[:type].to_s == "bar")
		end
		
		builder =
			Vega.lite
				.data(values: all_data)
				.params(params)
				.encoding(x: x_encoding)
				.layer(layers)
				.width(width)
				.height(height)
				.title(title)

		resolve_scale = {
			color: "independent"
			}

			resolve_scale[:y] = "independent" unless v2_array.empty?

		builder = builder.resolve(
			scale: resolve_scale
			)

		builder.embed_options(
			actions: { export: true, source: false, compiled: false, editor: false },
			scaleFactor: { png: 2, svg: 1 }
		)
	end

	def to_html(charts)
		## set .js
		#thedir = __dir__
		#
		#vegas = ["#{thedir}/vega.min.js",
		#	   "#{thedir}/vega-lite.min.js",
		#	   "#{thedir}/vega-embed.min.js"]
		
		asset_dir = File.join(__dir__, "vg_helper", "assets")
		vegas = [
			File.join(asset_dir, "vega.min.js"),
			File.join(asset_dir, "vega-lite.min.js"),
			File.join(asset_dir, "vega-embed.min.js")
		]

		vegas_lines = vegas.map { |vf|
		"<script>#{File.read(vf, encoding: 'utf-8')}</script>"
		}.join("\n")
		third_party_licenses = File.read(File.join(__dir__, "..", "THIRD_PARTY_LICENSES.txt"), encoding: "utf-8")

		## header, footer (No Slider Caption)
		html_head = <<-HTML
		<!doctype html>
		<html lang="ja">
		<head>
		  <meta charset="utf-8" />
		  <meta name="viewport" content="width=device-width, initial-scale=1" />
		  <title>Vega chart</title>
		  <!--
		#{third_party_licenses}
		  -->
		</head>
		<style>
		input[type=range]+span {
		  color: transparent !important;
		}

		.vega-bind {
		  display: inline-block !important;
		  margin-right: 20px;
		  vertical-align: middle;
		}
		</style>
		<body>
		<div id="vis"></div>
		#{vegas_lines}
		HTML

		html_foot = <<~'FOOT'
		</body>
		</html>
		FOOT

		html_head + [charts].flatten.map(&:to_s).join("\n") + html_foot
	end

	def write_htmls(charts, out)
		File.write(out, to_html(charts), encoding: "utf-8")
	end

end
