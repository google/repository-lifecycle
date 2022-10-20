// Copyright 2022 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import 'dart:async';
import 'dart:collection';

import 'package:built_value/built_value.dart';
import 'package:logging/logging.dart';
import 'package:meta/meta.dart';

import 'lifecycle_managed_service.dart';
import 'repository.dart';

part 'repository_lifecycle_manager.g.dart';

/// The amount of time the app is inactive before repositories are stopped.
///
/// Flutter will go inactive when certain native widgets appear onscreen. Quick
/// stop/starts of repositories are undesirable because most repositories always
/// refresh on start, so stopping immediately on inactive can actually cause
/// more polls to happen.
///
/// But repositories do have to be stopped eventually on inactive, because
/// sometimes events which we would expect to cause a pause only cause inactive,
/// i.e. pressing the phone lock button on a Pixel.
@visibleForTesting
const inactivityPeriod = Duration(seconds: 20);

/// A state of the app that hard blocks repositories from refreshing data.
abstract class RepositoryBlocker
    implements Built<RepositoryBlocker, RepositoryBlockerBuilder> {
  String get name;

  RepositoryBlocker._();
  factory RepositoryBlocker({required String name}) = _$RepositoryBlocker._;
}

/// Blocker for app lifecycle events.
///
/// When the app enters the foreground, this blocker is removed.
@visibleForTesting
final appLifecycle = RepositoryBlocker(name: 'appLifecycle');

/// Responsible for triggering mandatory actions on all repositories.
///
/// Instructions for use: extend this class, define any starting blockers in the
/// [customBlockers] parameter, and use your class to encapsulate adding and
/// removing blockers.
abstract class RepositoryLifecycleManager implements LifecycleManagedService {
  static final _log = Logger('RepositoryLifecycleManager');

  // These two log messages are used in integration tests to determine whether
  // the app has started up successfully.
  final String startReposLogMessage;
  final String stopReposLogMessage;

  @visibleForTesting
  final List<Repository> repositories = [];

  /// Whether repositories are currently stopped.
  var _isStopped = true;

  /// Timer to keep track of amount of time user has been in inactive state.
  Timer? _inactivityTimer;

  /// Current set of repository blockers.
  ///
  /// Starts with [appLifecycle] and any custom blockers provided in the
  /// constructor.
  @visibleForTesting
  final Set<RepositoryBlocker> blockers;

  RepositoryLifecycleManager({
    @deprecated UnmodifiableListView<Repository>? repositories,
    Set<RepositoryBlocker> customBlockers = const {},
    this.startReposLogMessage = 'Starting all repositories',
    this.stopReposLogMessage = 'Stopping all repositories',
  }) : blockers = {appLifecycle}.union(customBlockers) {
    if (repositories != null) {
      this.repositories.addAll(repositories);
    }
  }

  void registerRepository(Repository repository) {
    if (!repositories.contains(repository)) {
      repositories.add(repository);
    }
  }

  //
  // Implementation of LifecycleManagedService:
  //

  @override
  void onResume() {
    _cancelInactivityTimer();
    removeBlocker(appLifecycle);
  }

  @override
  void onPause() {
    _cancelInactivityTimer();
    addBlocker(appLifecycle);
  }

  @override
  void onInactive() {
    _log.info('App inactive: starting inactivity timer.');
    // After [_inactivityPeriod] of app being inactive, add the appLifecycle
    // blocker to stop repositories.
    if (!(_inactivityTimer?.isActive ?? false)) {
      _inactivityTimer = Timer(inactivityPeriod, () {
        addBlocker(appLifecycle);
      });
    }
  }

  //
  // Handling blockers:
  //

  void addBlocker(RepositoryBlocker blocker) {
    if (blockers.contains(blocker)) {
      return;
    }

    _log.info('Adding repository blocker: ${blocker.name}.');
    blockers.add(blocker);
    _stopRepos();
  }

  void removeBlocker(RepositoryBlocker blocker) {
    if (!blockers.contains(blocker)) {
      return;
    }

    _log.info('Removing repository blocker: ${blocker.name}.');
    blockers.remove(blocker);

    if (blockers.isEmpty) {
      _startRepos();
    } else {
      _log.info('Remaining repository blockers: $blockers');
    }
  }

  //
  // Repository interactions:
  //

  void _startRepos() {
    if (!_isStopped) return;
    _isStopped = false;
    _log.info(startReposLogMessage);
    for (var repo in repositories) {
      repo.start();
    }
  }

  void _stopRepos() {
    if (_isStopped) return;
    _isStopped = true;
    _log.info(stopReposLogMessage);
    for (var repo in repositories) {
      repo.stop();
    }
  }

  /// Clears data in all repositories.
  ///
  /// Descendants of this class must call super.clearData().
  void clearData() {
    _log.info('Clearing repository data');
    for (var repo in repositories) {
      repo.clear();
    }
  }

  //
  // Helper methods:
  //

  void _cancelInactivityTimer() {
    if (_inactivityTimer?.isActive ?? false) {
      _log.fine('Cancelling inactivity timer.');
      _inactivityTimer?.cancel();
      _inactivityTimer = null;
    }
  }
}
