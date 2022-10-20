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

import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:quiver/testing/async.dart';
import 'package:repository_lifecycle/repository.dart';
import 'package:repository_lifecycle/repository_lifecycle_manager.dart';
import 'package:test/test.dart';

import 'repository_lifecycle_manager_test.mocks.dart';

/// Concrete implementation of the abstract [RepositoryLifecycleManager]
class TestManager extends RepositoryLifecycleManager {
  TestManager({
    UnmodifiableListView<Repository>? repositories,
    Set<RepositoryBlocker> customBlockers = const {},
  }) : super(repositories: repositories, customBlockers: customBlockers);
}

@GenerateMocks([Repository])
void main() {
  final foo = RepositoryBlocker(name: 'foo');
  final bar = RepositoryBlocker(name: 'bar');
  final baz = RepositoryBlocker(name: 'baz');

  late UnmodifiableListView<Repository> repoList;
  late RepositoryLifecycleManager manager;
  late MockRepository repositoryA;
  late MockRepository repositoryB;

  setUp(() {
    repositoryA = MockRepository();
    repositoryB = MockRepository();

    repoList = UnmodifiableListView([repositoryA, repositoryB]);
    manager = TestManager(
      customBlockers: {foo},
    );
    manager.registerRepository(repositoryA);
    manager.registerRepository(repositoryB);
  });

  group('initialization', () {
    test('appLifecycle is the only blocker by default', () {
      manager = TestManager();

      expect(manager.blockers, {appLifecycle});
    });

    test('custom blockers are added to the blockers list', () {
      manager = TestManager(customBlockers: {bar, baz});

      expect(manager.blockers, {appLifecycle, bar, baz});
    });

    test('repositories can be registered via the constructor (for now)', () {
      expect(manager.repositories, {repositoryA, repositoryB});
      manager = TestManager(repositories: repoList);
      expect(manager.repositories, {repositoryA, repositoryB});
    });

    test('initially does not interact with repos', () {
      for (var repo in repoList) {
        verifyZeroInteractions(repo);
      }
    });
  });

  group('adding blockers', () {
    setUp(() {
      manager = TestManager();
      manager.registerRepository(repositoryA);
      manager.registerRepository(repositoryB);

      // Remove the app lifecycle blocker.
      manager.onResume();
    });

    test('adding a blocker calls stop on repositories', () {
      manager.addBlocker(bar);

      verify(repositoryA.stop()).called(1);
      verify(repositoryB.stop()).called(1);
    });

    test('adding multiple blockers calls stop on repositories only once', () {
      manager.addBlocker(foo);
      manager.addBlocker(bar);

      verify(repositoryA.stop()).called(1);
      verify(repositoryB.stop()).called(1);
    });
  });

  group('removing blockers', () {
    test('onResume removes appLifecycle blocker', () {
      expect(manager.blockers, {appLifecycle, foo});
      manager.onResume();
      expect(manager.blockers, {foo});
    });

    test('calling remove removes a blocker', () {
      expect(manager.blockers, {appLifecycle, foo});
      manager.removeBlocker(foo);
      expect(manager.blockers, {appLifecycle});
    });

    test('removing all blockers calls start on repositories', () {
      expect(manager.blockers, {appLifecycle, foo});

      manager.removeBlocker(appLifecycle);
      manager.removeBlocker(foo);
      verify(repositoryA.start());
      verify(repositoryB.start());
    });
  });

  group('clear', () {
    test('calling clearData calls clear on all repositories', () {
      manager.clearData();
      verify(repositoryA.clear());
      verify(repositoryB.clear());
    });
  });

  group('blockers plus lifecycle', () {
    setUp(() {
      manager.addBlocker(foo);
      // Remove the app lifecycle blocker.
      manager.onResume();
    });

    test('does not start repos on valid profile if app is paused', () {
      manager.onPause();

      for (var repo in repoList) {
        verifyNever(repo.start());
      }
    });

    test('does not stop repos on blocker removal if app is paused', () {
      // Start repos and then pause the app.
      manager.removeBlocker(foo);
      manager.onPause();
      repoList.forEach(clearInteractions);

      // This should not do anything; already stopped.
      manager.addBlocker(foo);
      manager.removeBlocker(foo);

      for (var repo in repoList) {
        verifyNever(repo.stop());
      }
    });
  });

  group('appLifecycle', () {
    setUp(() {
      // Remove the [foo] blocker.
      manager.removeBlocker(foo);
    });

    test('calls start when app is resumed', () {
      manager.onResume();

      for (var repo in repoList) {
        verify(repo.start()).called(1);
      }
    });

    test('calls stop when app is paused', () {
      manager.onResume();
      repoList.forEach(clearInteractions);

      manager.onPause();

      for (var repo in repoList) {
        verify(repo.stop()).called(1);

        // Should not have called clear or anything else.
        verifyNoMoreInteractions(repo);
      }
    });

    test('does not redundantly call start', () {
      manager.onResume();
      manager.onResume();

      for (var repo in repoList) {
        verify(repo.start()).called(1);
      }
    });

    test('does not start repos onResume if a blocker is present', () {
      manager.addBlocker(bar);
      manager.onResume();
      expect(manager.blockers, {bar});

      for (var repo in repoList) {
        verifyNever(repo.start());
      }
    });

    test('does not stop repos onPause if profile is not valid', () {
      // Start repos and then add [foo] again.
      manager.onResume();
      manager.addBlocker(foo);
      repoList.forEach(clearInteractions);

      // Pause should not do anything; already stopped.
      manager.onPause();

      for (var repo in repoList) {
        verifyNever(repo.stop());
      }
    });
  });

  group('onInactive', () {
    final halfInterval = inactivityPeriod ~/ 2;

    setUp(() {
      // Remove blockers
      manager.removeBlocker(foo);
      manager.onResume();
      repoList.forEach(clearInteractions);
    });

    void asyncTest(
        String name, Future<void> Function(FakeAsync) testBody) async {
      test(name, () async {
        final completer = Completer<void>();
        FakeAsync()
          ..run((time) async {
            try {
              await testBody(time);
            } finally {
              completer.complete();
            }
          })
          ..flushTimers();
        await completer.future;
      });
    }

    asyncTest('stops repos after interval', (time) async {
      manager.onInactive();

      // Does nothing immediately.
      for (var repo in repoList) {
        verifyNever(repo.stop());
      }

      time.elapse(inactivityPeriod);

      for (var repo in repoList) {
        verify(repo.stop()).called(1);
      }
    });

    asyncTest('cancels timer onPause', (time) async {
      manager.onInactive();

      time.elapse(halfInterval);

      // Should stop repos immediately and cancel timer.
      manager.onPause();
      for (var repo in repoList) {
        verify(repo.stop()).called(1);
      }

      // After full interval is finished, no more calls to repositories.
      time.elapse(halfInterval);
      repoList.forEach(verifyNoMoreInteractions);
    });

    asyncTest('cancels timer onResume', (time) async {
      manager.onInactive();

      // App resumes before time is up.
      time.elapse(halfInterval);
      manager.onResume();

      time.elapse(halfInterval);
      // Should never have called stop on repos.
      repoList.forEach(verifyNoMoreInteractions);
    });

    asyncTest('multiple calls do not restart timer', (time) async {
      manager.onInactive();

      time.elapse(halfInterval);

      // Repeat call. Timer should still finish after original interval.
      manager.onInactive();

      // Verify timer finishes.
      time.elapse(halfInterval);
      for (var repo in repoList) {
        verify(repo.stop()).called(1);
      }

      // Verify another timer was not started.
      time.elapse(halfInterval);
      repoList.forEach(verifyNoMoreInteractions);
    });
  });

  test('spam test', () {
    manager.onPause();
    manager.onInactive();

    manager.removeBlocker(foo);
    // Next line triggers clear().
    manager.clearData();
    manager.addBlocker(baz);

    manager.onResume();

    // Next line triggers start().
    manager.removeBlocker(baz);
    manager.removeBlocker(baz);

    manager.onInactive();
    // Next line triggers stop().
    manager.onPause();

    // Next line triggers clear().
    manager.clearData();
    manager.addBlocker(bar);
    manager.onResume();

    for (var repo in repoList) {
      verify(repo.start()).called(1);
      verify(repo.stop()).called(1);
      verify(repo.clear()).called(2);
    }
  });
}
