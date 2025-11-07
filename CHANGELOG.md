## 1.0.0

- Initial version

## 1.1.0

- Change the interface

## 1.3.1

- Change the tracker interfaces and add a new dependency

## 1.3.4

- Add IPv6 support
- Make tracker and scrape can re-try
- Change Readme and example
- Delete useless files

## 1.3.6

- Fix a http tracker bug

## 1.3.11

- Remove 'timeout' retry future.
- Add 'Error happen' retry future.
- Change HttpTracker

## 1.3.12

- Add 'complete' method

## 1.3.14

- Migrate to null safety
- Some linting and code style changes

## 1.3.15
- pub.dev fixes

## 1.3.16
- migrate to events_emitter2

## 1.3.17
- use the new legal test torrents
- update deps and sdk constraints

## 1.3.18
- use logging package

## 1.3.19
- Migrate package name to dtorrent_tracker_v2
- Fix HttpTracker stop() and complete() events not being sent to announce server
- Update all imports to use new package name
- Update lints to ^6.0.0
- Fix analyzer warnings: add type annotations and fix doc comments
- Update README

## 1.4.0
- Fix IPv6 parsing in UDP tracker
- Implement UDP tracker timeout mechanism (TIME_OUT constant was defined but never used)
- Add timeout tests for UDP tracker
- Fix UDP retry mechanism: implement proper retry limit with exponential backoff (maxConnectRetryTimes was defined but never used)