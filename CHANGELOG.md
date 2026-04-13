# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2026-04-13

### Added
- Added an optional Yabeda adapter so Yabeda-defined metrics can be delivered through the gem's async CloudWatch reporter pipeline.
- Added Yabeda-focused smoketest coverage, including parity checks against the stock Yabeda plugin flow.
- Added a `mise lint` task for local development.

### Changed
- Reduced CloudWatch metric cardinality and cost by removing the `WorkerIndex`, `Tag`, and `Hostname` dimensions from the affected Puma and Sidekiq metrics.
- Refactored shared metric collection into observation helpers to keep collector behavior aligned across integrations and smoketests.
- Expanded the README with setup and behavior notes for Yabeda-backed metrics.

### Fixed
- Preserved the first Yabeda metric after process forks.
- Honored Yabeda gauge aggregation hints when mapping values to CloudWatch.
- Improved smoketest isolation and child-process propagation for Yabeda scenarios.

### Upgrade Notes
- Existing CloudWatch dashboards or alarms that filter on `WorkerIndex`, `Tag`, or `Hostname` dimensions will need to be updated before upgrading.

## [0.1.0] - 2025-11-17

### Added
- Initial public release.

[0.2.0]: https://github.com/speedshop/speedshop-cloudwatch/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/speedshop/speedshop-cloudwatch/releases/tag/v0.1.0
