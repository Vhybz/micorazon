# Implementation Plan - Global System Synchronization (Database Adjustments)

To make features like **System Lockdown** and **Global Activity Monitoring** truly "real" and synchronized across all devices in your company, we need to transition from local app state to a shared database state.

## User Review Required

> [!IMPORTANT]
> You will need to execute a SQL script in your Supabase SQL Editor to create the necessary tables for global settings and audit tracking.

## Proposed Changes

### [Database Layer]

#### [NEW] `system_settings` Table
- Create a new table to store company-wide configurations.
- Columns:
    - `id`: primary key (fixed ID `global`)
    - `is_lockdown_active`: boolean (Default: `false`)
    - `last_updated`: timestamp
    - `updated_by`: user ID of the Super Admin

#### [REFINE] `audit_logs` Table
- Ensure your existing `audit_logs` table has the following structure to support the "Before/After" comparison:
    - `old_data`: JSONB (nullable)
    - `new_data`: JSONB (nullable)

### [Core Services]

#### [NEW] [system_settings_provider.dart](file:///C:/Users/USER/StudioProjects/ms/lib/services/system_settings_provider.dart)
- Create a `SystemSettingsNotifier` that:
    - Listens to a real-time Supabase stream on the `system_settings` table.
    - Provides a method `toggleLockdown(bool status)` to update the remote database.

#### [MODIFY] [passcode_guard.dart](file:///C:/Users/USER/StudioProjects/ms/lib/widgets/passcode_guard.dart)
- Replace the local `systemLockdownProvider` with the new remote `systemSettingsProvider`.
- This ensures that if a Super Admin activates lockdown, every connected device will see the change instantly via the stream.

#### [MODIFY] [super_admin_screen.dart](file:///C:/Users/USER/StudioProjects/ms/lib/screens/admin/super_admin_screen.dart)
- Connect the **System Lockdown** button to the new remote toggle method.

## SQL Initialization Script

```sql
-- Create System Settings Table
CREATE TABLE IF NOT EXISTS public.system_settings (
    id TEXT PRIMARY KEY DEFAULT 'global',
    is_lockdown_active BOOLEAN DEFAULT false,
    updated_at TIMESTAMPTZ DEFAULT now(),
    updated_by UUID REFERENCES auth.users(id)
);

-- Insert initial record
INSERT INTO public.system_settings (id, is_lockdown_active)
VALUES ('global', false)
ON CONFLICT (id) DO NOTHING;

-- Enable Realtime for this table
ALTER PUBLICATION supabase_realtime ADD TABLE system_settings;
```

## Verification Plan

### Manual Verification
1.  **Multi-Device Lockdown**: Log in on two different devices. On one (as Super Admin), activate "System Lockdown". Verify that the second device is immediately forced to the lock screen.
2.  **Persistence**: Activate lockdown, close the app entirely, and reopen it. Verify that it boots directly into the lock screen.
3.  **Audit Integrity**: Verify that complex actions (like stock edits) correctly populate the `old_data` and `new_data` columns in the `audit_logs` table.
