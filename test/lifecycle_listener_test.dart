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

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:repository_lifecycle/lifecycle_listener.dart';
import 'package:repository_lifecycle/lifecycle_managed_service.dart';

import 'lifecycle_listener_test.mocks.dart';

@GenerateMocks([
  LifecycleManagedService,
], customMocks: [
  MockSpec<LifecycleManagedService>(as: #OtherMockLifecycleService),
])
void main() {
  late MockLifecycleManagedService lifecycleService;
  late OtherMockLifecycleService otherLifecycleService;
  late LifecycleListener lifecycleListener;
  late List<LifecycleManagedService> lifecycleServices;

  setUp(() {
    lifecycleService = MockLifecycleManagedService();
    otherLifecycleService = OtherMockLifecycleService();
    lifecycleServices = [lifecycleService, otherLifecycleService];
    lifecycleListener = LifecycleListener.forTest(services: lifecycleServices);
  });

  Future<void> setUpWidget(
    WidgetTester tester, {
    AppLifecycleState state = AppLifecycleState.resumed,
  }) async {
    tester.binding.handleAppLifecycleStateChanged(state);
    await tester.pumpWidget(lifecycleListener);
    // Ensure that the widget tree is mounted regardless of the lifecycle state.
    tester.binding.scheduleWarmUpFrame();
  }

  testWidgets('services are resumed by default', (tester) async {
    await setUpWidget(tester);

    // Resume called once on startup, inactive and pause never called:
    for (var service in lifecycleServices) {
      verify(service.onResume()).called(1);
      verifyNever(service.onInactive());
      verifyNever(service.onPause());
      verifyNoMoreInteractions(service);
    }
  });

  testWidgets('services are inactive by default if inactive', (tester) async {
    await setUpWidget(tester, state: AppLifecycleState.inactive);

    for (var service in lifecycleServices) {
      verifyNever(service.onResume());
      verify(service.onInactive()).called(1);
      verifyNever(service.onPause());
      verifyNoMoreInteractions(service);
    }
  });

  testWidgets('services are paused by default if detached', (tester) async {
    await setUpWidget(tester, state: AppLifecycleState.detached);

    for (var service in lifecycleServices) {
      verifyNever(service.onResume());
      verifyNever(service.onInactive());
      verify(service.onPause()).called(1);
      verifyNoMoreInteractions(service);
    }
  });

  testWidgets('services are not paused when inactive', (tester) async {
    await setUpWidget(tester);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpAndSettle();

    for (var service in lifecycleServices) {
      // Resume and inactive called once on startup, pause never called:
      verifyInOrder([
        service.onResume(),
        service.onInactive(),
      ]);
      verifyNever(service.onPause());
      verifyNoMoreInteractions(service);
    }
  });

  testWidgets('services are paused when paused', (tester) async {
    await setUpWidget(tester);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpAndSettle();

    for (var service in lifecycleServices) {
      // Resume called once on startup, inactive and pause called once on state
      // change:
      verifyInOrder([
        service.onResume(),
        service.onInactive(),
        service.onPause(),
      ]);
      verifyNoMoreInteractions(service);
    }
  });

  testWidgets('services are resumed after pausing', (tester) async {
    await setUpWidget(tester);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    for (var service in lifecycleServices) {
      // Resume called twice:
      //   - once on startup
      //   - once on state change back to resumed
      //
      // Inactive and pause called once:
      //   - once on state change to inactive then change to paused
      verifyInOrder([
        service.onResume(),
        service.onInactive(),
        service.onPause(),
        service.onResume(),
      ]);
      verifyNoMoreInteractions(service);
    }
  });
}
