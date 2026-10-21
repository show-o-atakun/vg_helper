## [Unreleased]

### Added

- Enable PNG (2x resolution) and SVG downloads from the actions menu for
  date and nominal charts, including offline HTML and IRuby output.

### Fixed

- Read bundled JavaScript and write standalone HTML as UTF-8 to preserve
  runtime strings and Japanese chart text.

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
