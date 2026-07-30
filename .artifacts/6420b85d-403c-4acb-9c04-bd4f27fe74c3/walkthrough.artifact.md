# Walkthrough - System Lock & Passcode Guidance

I have enhanced the security system with a manual "System Lock" and improved the guidance for staff members entering their passcodes.

## Changes Made

### [UI Components]

#### [main_app_bar.dart](file:///C:/Users/USER/StudioProjects/ms/lib/widgets/main_app_bar.dart)
- **Manual Lock Icon**: Added a **Lock Icon** (`Icons.lock_outline_rounded`) to the top-right actions area.
- **One-Tap Security**: Tapping this icon immediately locks the app and requires a 4-digit passcode to continue, perfect for when a staff member steps away from the terminal.

#### [passcode_guard.dart](file:///C:/Users/USER/StudioProjects/ms/lib/widgets/passcode_guard.dart)
- **Smart Delivery Info**: The lock screen now shows exactly when the user's passcode was sent and to which phone number (e.g., *"Code sent to phone ending in 200 on July 28 at 10:30 AM"*).
- **Locked Switcher**: Added a **"SWITCH ACCOUNT"** button below the keypad. This ensures that even if one user forgets their code or leaves the system locked, another staff member can take over by switching to their own profile.

#### [account_switch_dialog.dart](file:///C:/Users/USER/StudioProjects/ms/lib/widgets/account_switch_dialog.dart)
- **Selection Guidance**: When switching accounts, the keypad now shows the delivery information for the *selected* user, helping them locate their code in their SMS history.

### [Data & Logic]

#### [user_model.dart](file:///C:/Users/USER/StudioProjects/ms/lib/models/user_model.dart)
- **Timestamp Tracking**: Added the `passcodeSentAt` field to the user profile to record the exact moment of delivery.

#### [user_provider.dart](file:///C:/Users/USER/StudioProjects/ms/lib/services/user_provider.dart)
- **Automatic Logging**: The system now automatically records the current date and time whenever an Admin updates or sets a staff member's passcode.

## Verification Results

- **System Lock**: Verified that tapping the lock icon instantly triggers the security guard across all protected screens.
- **Privacy Shield**: Confirmed that phone numbers are obfuscated (e.g., `...200`) on the lock screen for security.
- **Seamless Switching**: Verified that clicking "SWITCH ACCOUNT" on the lock screen correctly opens the staff list and allows profile swapping.

> [!TIP]
> Encourage your staff to **tap the Lock icon** whenever they step away from the scale or POS to keep your records secure!
