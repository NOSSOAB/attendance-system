package com.faceauth.thinclient;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

public class SessionOperationGuardTest {
    @Test
    public void stopInvalidatesPendingCreateCallback() {
        SessionOperationGuard guard = new SessionOperationGuard();
        long pendingCreate = guard.begin();

        guard.cancel();

        assertFalse(guard.isCurrent(pendingCreate));
    }

    @Test
    public void newerCreateInvalidatesOlderCreateCallback() {
        SessionOperationGuard guard = new SessionOperationGuard();
        long firstCreate = guard.begin();
        long secondCreate = guard.begin();

        assertFalse(guard.isCurrent(firstCreate));
        assertTrue(guard.isCurrent(secondCreate));
    }

    @Test
    public void conditionalCancelCannotCancelNewerOperation() {
        SessionOperationGuard guard = new SessionOperationGuard();
        long oldSession = guard.begin();
        long newSession = guard.begin();

        assertFalse(guard.cancelIfCurrent(oldSession));
        assertTrue(guard.isCurrent(newSession));
    }

    @Test
    public void conditionalCancelInvalidatesMatchingOperation() {
        SessionOperationGuard guard = new SessionOperationGuard();
        long activeSession = guard.begin();

        assertTrue(guard.cancelIfCurrent(activeSession));
        assertFalse(guard.isCurrent(activeSession));
    }
}
