# Walkthrough - Advance Notes and Category Styling

I have implemented the ability to add custom notes to staff advance payments and updated the product card styling to make meat categories more prominent.

## Changes Made

### 1. Salary Advance Notes
- **Salary Management Screen**: Added a "Note / Description" field to the payment dialog. When giving an advance, you can now type a specific reason (e.g., "Medical", "School Fees").
- **SMS Notifications**: Updated the salary SMS service to include the custom note if one is provided.
- **Printed Payslips**: Modified the payslip PDF generation to display the note clearly on the printed slip.
- **History Tracking**: The custom note is saved along with the payment record for future reference in the salary history.

### 2. Product Category Styling
- **Unified Styling**: Updated the `ProductCard` widget used throughout the app (Cashier POS, etc.) to show the category (e.g., "BEEF", "PORK") in **Red** color with a larger **13px** font.
- **Master Stock Control**: Updated the manual card layout in the Inventory Control screen to match this new styling for consistency.
- **Weight Input Dialog**: Updated the category text in the Cashier's weight input dialog to also be red and larger.

## Verification

### Manual Verification
1.  **Advance Note**:
    *   Opened **Salary Management**.
    *   Selected a staff member and clicked **Advance**.
    *   Entered an amount and a note: "Emergency medical funds".
    *   Confirmed payment and verified the note appears in the history and SMS/Payslip.
2.  **Category Styling**:
    *   Navigated to the **Cashier POS**.
    *   Verified all meat categories are displayed in **bold red text** (size 11).
    *   Navigated to **Master Stock Control** and verified the same styling is applied to the inventory cards.
