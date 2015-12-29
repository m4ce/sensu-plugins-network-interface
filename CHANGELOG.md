# Change Log
This project adheres to [Semantic Versioning](http://semver.org/).

This CHANGELOG follows the format listed at [Keep A Changelog](http://keepachangelog.com/)

## Unreleased

## [0.1.7] - 2015-12-29
### Added
- Fixed wrong logic when populating interface_config from ifcfg files

## [0.1.6] - 2015-12-29
### Added
- No longer send UNKNOWN events when metrics cannot be computed for specific interface (e.g. speed & bridge interfaces)
- Filter out dummy interfaces as well as loopback ones.

## [0.1.5] - 2015-12-29
### Added
- Fixed typo

## [0.1.4] - 2015-12-29
### Added
- Added ifcfg support (supplement optional JSON configuration file)

## [0.1.3] - 2015-12-28
### Added
- Requiring json globally

## [0.1.2] - 2015-12-28
### Added
- Defaulting @json_config to empty hash

## [0.1.1] - 2015-12-28
### Added
- Initial release
