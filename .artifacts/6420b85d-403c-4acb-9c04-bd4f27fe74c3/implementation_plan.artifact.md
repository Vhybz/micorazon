# Implementation Plan - System Lock & Passcode Guidance

This plan introduces a manual system lock feature and provides clear guidance on the passcode entry screen about when and where codes were sent.

## User Review Required

> [!IMPORTANT]
> - **System Lock**: A lock icon will be added to the top App Bar. Clicking it will immediately lock the current terminal.
> - **Locked State**: When locked, the system will only allow entering the passcode OR switching to another staff member's account.
> - **Passcode Delivery Info**: The lock screen will display exactly when the passcode was sent and to which phone number (e.g., `Sent to XXXXXX123 on July 28 at 10:30 AM`).

## Proposed Changes

### [Models]
#### [MODIFY] [user_model.dart](file:///C:/Users/USER/StudioProjects/ms/lib/models/user_model.dart)
- Add `passcodeSentAt` (DateTime?) to `UserAccount`.
- Update serialization and `copyWith`.

### [Services]
#### [MODIFY] [user_provider.dart](file:///C:/Users/USER/StudioProjects/ms/lib/services/user_provider.dart)
- Update `updatePasscode` to save the current timestamp in `passcode_sent_at`.

### [UI Components]
#### [MODIFY] [main_app_bar.dart](file:///C:/Users/USER/StudioProjects/ms/lib/widgets/main_app_bar.dart)
- Add a Lock icon (`Icons.lock_outline_rounded`) to the header.
- Logic: On tap, set `passcodeUnlockedProvider` to `false`.

#### [MODIFY] [passcode_guard.dart](file:///C:/Users/USER/StudioProjects/ms/lib/widgets/passcode_guard.dart)
- Display delivery info: *"A code was sent to your phone number ending in [XXX] on [Date] at [Time]. Contact Admin if there is any issue."*
- Add a "SWITCH ACCOUNT" button to the bottom of the keypad screen to allow other staff to take over while the system is locked.

#### [MODIFY] [account_switch_dialog.dart](file:///C:/Users/USER/StudioProjects/ms/lib/widgets/account_switch_dialog.dart)
- Display the same delivery info for the selected user.

## Verification Plan

### Manual Verification
1. **Manual Lock**: Tap the lock icon in the top bar. Verify the app immediately shows the passcode entry screen.
2. **Guidance Message**: Check that the message correctly shows the last 3 digits of your phone and the correct date/time the code was set.
3. **Switch While Locked**: Verify that you can click "SWITCH ACCOUNT" on the lock screen and pick another staff member.
4. **Account Switch Info**: Verify the account switcher also shows the delivery info for the target user.
