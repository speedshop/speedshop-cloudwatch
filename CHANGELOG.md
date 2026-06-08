# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.1] - 2026-06-09

### Fixed
- Improved Rack request queue time parsing for common `X-Request-Start` and `X-Queue-Start` formats, including `t=` prefixes, seconds, milliseconds, microseconds, and comma-separated header values.
- Subtracted Puma request body wait time from Rack queue time when `env["puma.request_body_wait"]` is available, so slow uploads are not counted as upstream queueing.

## [0.2.0] - 2026-04-13

### Added
- Added an optional Yabeda adapter so Yabeda-defined metrics can be delivered through the gem's async CloudWatch reporter pipeline.

### Changed
- Reduced CloudWatch metric cardinality and cost by removing the `WorkerIndex`, `Tag`, and `Hostname` dimensions from the affected Puma and Sidekiq metrics.

### Upgrade Notes
- Existing CloudWatch dashboards or alarms that filter on `WorkerIndex`, `Tag`, or `Hostname` dimensions will need to be updated before upgrading.

## [0.1.0] - 2025-11-17

### Added
- Initial public release.

[0.2.1]: https://github.com/speedshop/speedshop-cloudwatch/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/speedshop/speedshop-cloudwatch/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/speedshop/speedshop-cloudwatch/releases/tag/v0.1.0
