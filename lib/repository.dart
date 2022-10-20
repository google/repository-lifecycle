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

import 'repository_lifecycle_manager.dart';

/// Common interface for repositories that store user data.
abstract class Repository {
  /// Immedaitely registers itself with the [RepositoryLifecycleManager].
  ///
  /// This reduces DI boilerplate.
  Repository([RepositoryLifecycleManager? manager]) {
    manager?.registerRepository(this);
  }

  /// Starts any automatic actions the repository is responsible for, i.e.
  /// polling for data updates or responding to cache invalidations.
  void start();

  /// Stops all automatic actions.
  ///
  /// Stopped repositories should not poll or respond to cache invalidations.
  /// They should fetch data only in response to a specific request from a
  /// caller.
  void stop();

  /// Clears the repository's data.
  ///
  /// This function should only be called when the repository is stopped. If it
  /// is called, the repository should clear as much of its in-memory data as
  /// possible (i.e, data in behavior subjects). It should make sure that
  /// calling start() will trigger an immediate refresh of data.
  ///
  /// Be wary of any actions that will send null on a subject, as this may have
  /// unexpected consequences/result in NPEs. Same for reinstantiating a
  /// subject, since someone might be listening to the old one.
  void clear();
}
