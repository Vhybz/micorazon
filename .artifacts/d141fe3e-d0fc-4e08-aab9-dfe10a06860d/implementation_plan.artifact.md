# Implementation Plan - Passcode Guidance & Safety

This plan ensures that users who haven't set a security PIN are guided on how to do so when they try to use the system lock feature, rather than experiencing a silent bypass.

## User Review Required

> [!NOTE]
> Users without a PIN will see a guidance message (SnackBar) instead of a lock screen. This prevents confusion and encourages better security practices.

## Proposed Changes

### [UI Components]

#### [MODIFY] [MainAppBar](file:///C:/Users/USER/StudioProjects/ms/lib/widgets/main_app_bar.dart)
- In the lock icon's `onTap`:
    - Check if the current user has a `passcode` set.
    - If `user.passcode == null`, show a `SnackBar`: *"Security Passcode not set. Please set a 4-digit PIN in Staff Management to enable system locking."*
    - If `user.passcode != null`, proceed with the immediate lock (`ref.read(passcodeUnlockedProvider.notifier).state = false`).

#### [MODIFY] [PasscodeGuard](file:///C:/Users/USER/StudioProjects/ms/lib/widgets/passcode_guard.dart)
- Update the `build` method to handle the (unlikely) case where a user is locked but has no passcode:
    - If `user.passcode == null`, display a clear instruction message: *"No Security PIN found. Please contact an Administrator to reset your PIN or switch to an authorized account."*
    - This provides a "dead-end" safety net if a PIN is removed while a session is active.

## Verification Plan

### Manual Verification
1. **User WITH PIN**: Tap the lock icon. Verify the system locks immediately.
2. **User WITHOUT PIN**: Tap the lock icon. Verify the guidance SnackBar appears and the screen does *not* lock.
3. **PIN Removal Test**: While a user is on the lock screen (using another device or admin), remove their PIN. Verify the lock screen updates to show the "No Security PIN found" guidance instead of just a keypad that won't work.
