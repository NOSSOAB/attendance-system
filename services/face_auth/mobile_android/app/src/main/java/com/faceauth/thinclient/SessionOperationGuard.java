package com.faceauth.thinclient;

/**
 * Monotonic cancellation token for asynchronous session operations.
 *
 * A newly started or cancelled operation invalidates every older callback, so
 * a delayed HTTP response cannot reactivate a session after the user pressed
 * Stop or started a replacement session.
 */
final class SessionOperationGuard {
    private long generation = 0L;

    synchronized long begin() {
        generation += 1L;
        return generation;
    }

    synchronized void cancel() {
        generation += 1L;
    }

    synchronized boolean cancelIfCurrent(long operationId) {
        if (generation != operationId) {
            return false;
        }
        generation += 1L;
        return true;
    }

    synchronized boolean isCurrent(long operationId) {
        return generation == operationId;
    }
}
