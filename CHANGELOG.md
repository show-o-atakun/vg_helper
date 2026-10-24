## [Unreleased]

## [0.1.3.pre.1] - 2026-10-24

Preview release for testing the upcoming 0.1.3 with real data.
Normal installs continue to select the latest stable release.

### Added

- Enable PNG (2x resolution) and SVG downloads from the actions menu for
  date and nominal charts, including offline HTML and IRuby output.
- Add `VGHelper.to_html` for editable standalone HTML strings; delegate
  `write_htmls` to it.
- Warn with column names and counts for NaN in either DataFrame. Retain
  rows and original inputs, using null only in the generated chart data.
- Add `miny2` / `maxy2` for explicit secondary-axis domains.
- Add first-axis category stacking for bars with stack-aware bounds and
  statistics; `stack: false` disables stacking.
- Add `markkind2` for secondary-axis presets and custom marks, keeping
  bars as the default. Line and point statistics use observations.

### Fixed

- Include upstream runtime license notices in the gem and standalone HTML.
- Read bundled JavaScript and write standalone HTML as UTF-8 to preserve
  runtime strings and Japanese chart text.
- Normalize numeric categories and explicit category lists to strings.

## [0.1.0] - 2026-08-13

- Initial release

## 0.1.2 - 2026-09-13

### Added

- Added mark presets:
  - `:line`
  - `:line_dot`
  - `:small_dot`
  - `:large_dot`
  - `:bar`

### Fixed

- Improved category filtering for category names containing special characters.
- Unified main-axis styling when horizontal reference lines are used with a secondary y-axis.
