# Implementation Plan - Default Unit and Value for Goat Head in Butcher Breakdown

This plan addresses the request to default "Head" to a quantity of 1 (instead of kg) when breaking down a carcass in the Butcher unit, specifically for Goats.

## Proposed Changes

### [Component] Butcher Carcass Breakdown

#### [MODIFY] [carcass_breakdown_screen.dart](file:///C:/Users/USER/StudioProjects/ms/lib/screens/butcher/carcass_breakdown_screen.dart)
- Update the `initState` method:
    - Check if the current animal type is `AnimalType.goat` (or apply generally to any animal with a "Head" cut if appropriate).
    - When initializing controllers for standard cuts, if the cut name is "Head":
        - Set its unit to "Qty" instead of "kg".
        - Set the default value of the controller to "1".
    - (Optional but recommended) Consider doing the same for "Feet" with a default of 4, although not explicitly requested. *Decision: I will only implement it for "Head" as requested to avoid over-engineering, but I'll make the logic clean so "Feet" could be added easily.*

## Verification Plan

### Manual Verification
1.  **Butcher Carcass Breakdown**:
    *   Log in as a Butcher.
    *   Navigate to **Slaughter Logs**.
    *   Select a **Goat** slaughter log that is ready for breakdown.
    *   Verify that the "Head" input field:
        - Defaults to **Qty** (blue label).
        - Has an initial value of **1**.
        - Does not contribute to the "REMAINING" weight total (since it's a unit, not kg).
    *   Save the breakdown and verify it proceeds correctly.
