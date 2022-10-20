# Repository Lifecycle

This package contains the class definitions for the repository pattern, which
encapsulates a Flutter app's data caching and retry logic, and provides a way
for non-Widget Dart objects to receive and respond to app lifecycle events.

The elements of this pattern include:

*   **Repository**: A repository is responsible for all caching and retry logic
    for a given data type. It's also responsible for polling or responding to
    cache invalidations to update the cached data. A repository may have a
    one-to-many relationship with RPCs. It also has methods to **start** and
    **stop** its polling or cache invalidations, and has a method to **clear**
    its caches.
*   **Repository Manager**: A repository manager maintains a list of
    repositories. This class will use a combination of app lifecycle events
    (entering foreground / background) and in-app events to call **start**,
    **stop** and **clear** on the repositories in the list.
*   **LifecycleManagedService**: This is an interface for a class that should
    receive app lifecycle events.
*   **LifecycleListener**: This is a Widget that accepts a list of
    LifecycleManagedService objects. The listener registers for lifecycle
    events, and when one happens, it triggers the callback for every
    LifecycleManagedService in the list.

The RepositoryManager object is a LifecycleManagedService, and will use those
callbacks in combination with in-app events to make the start, stop and clear
calls for repositories.

As a very rough example, after the app enters the foreground, and the user has
successfully signed in, the RepositoryManager will call `start` on its list of
repositories. The contract is: `start` will only be called when it's safe to
start making RPCs.

Note: This is not an officially supported Google product.
