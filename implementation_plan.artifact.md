# Implementation Plan - Enhanced Transaction History

The goal is to enhance the Transaction History view in the POS with business KPIs (Sales, Profit), a sorted list of top-performing products, and a visual sales trend graph.

## User Review Required

> [!IMPORTANT]
> - A new **KPI section** will be added to the top of the history view, showing Total Sales and Total Profit for the selected period.
> - A **Sales Trend Graph** will be included to visualize daily performance over the last 7 days (or selected range).
> - A **"Highest Purchased Products"** section will be added, showing products sorted by quantity sold in descending order.

## Proposed Changes

### 1. Cashier POS: History View Refactoring
#### [MODIFY] [cashier_pos.dart](file:///C:/Users/USER/StudioProjects/ms/lib/screens/cashier/cashier_pos.dart)
- Update `_buildHistoryLayout` to include:
    - `_buildHistoryKPIs(totalSales, totalProfit)`
    - `_buildHistorySalesChart(filteredHistory)`
    - `_buildTopProductsList(productQtyMap)`
- Ensure the layout remains responsive and fits well on mobile devices.

### 2. Logic Updates
#### [MODIFY] [cashier_pos.dart](file:///C:/Users/USER/StudioProjects/ms/lib/screens/cashier/cashier_pos.dart)
- Enhance the calculation block in `_buildHistoryLayout` to group sales by day for the chart.
- Sort the `productQtyMap` entries to identify the "Highest Purchased Products".

## Verification Plan

### Manual Verification
1.  **KPI Check**: Filter by "Today". Verify the Total Sales and Profit match the expected values from the individual transactions.
2.  **Product Sorting**: Check the "Top Products" list. Verify the product with the most units sold is at the top.
3.  **Graph Accuracy**: Verify the bars in the graph correctly represent the daily sales totals.
4.  **Responsiveness**: Ensure the chart and summary cards don't cause horizontal overflow on mobile.
