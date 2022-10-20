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
import 'package:logging/logging.dart';

import 'lifecycle_managed_service.dart';

final _log = Logger('LifecycleListener');

/// A top level widget that listens for lifecycle event changes.
class LifecycleListener extends StatefulWidget {
  final Widget child;
  final Iterable<LifecycleManagedService> services;

  const LifecycleListener({
    required this.services,
    required this.child,
  });

  @visibleForTesting
  const LifecycleListener.forTest({
    required this.services,
  }) : child = const SizedBox();

  @override
  _LifecycleListenerState createState() => _LifecycleListenerState();
}

class _LifecycleListenerState extends State<LifecycleListener>
    with WidgetsBindingObserver {
  AppLifecycleState _state = AppLifecycleState.resumed;

  @override
  void initState() {
    super.initState();

    _state = WidgetsBinding.instance.lifecycleState!;

    WidgetsBinding.instance.addObserver(this);

    widget.services.forEach(_notifyLifecycleState);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _state = state;
    widget.services.forEach(_notifyLifecycleState);
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }

  void _notifyLifecycleState(LifecycleManagedService service) {
    switch (_state) {
      case AppLifecycleState.resumed:
        service.onResume();
        break;
      case AppLifecycleState.inactive:
        // Use this carefully since we don't want to pause most of things when
        // inactive, because inactive handles the following:
        //
        // "Apps transition to this state when another activity is focused, such
        // as a split-screen app, a phone call, a picture-in-picture app, a
        // system dialog, or another window."
        service.onInactive();
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        service.onPause();
        break;
      default:
        _log.shout('Unknown app lifecycle state: $_state');
        break;
    }
  }
}
