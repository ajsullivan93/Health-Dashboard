# Native iOS HealthKit app

Safari and normal PWAs cannot access HealthKit. The SwiftUI wrapper in this folder is the required native integration.

## Build and install

1. On a Mac, open Xcode 15 or later and create an iOS App named HealthDashboard using SwiftUI and an iOS 16 deployment target.
2. Add HealthDashboardApp.swift and HealthKitSyncManager.swift to the app target.
3. Add the repository root index.html to the target with Copy items if needed enabled. The app loads the bundled dashboard in WKWebView.
4. In Signing and Capabilities, add the HealthKit capability.
5. Add NSHealthShareUsageDescription to Info.plist explaining that the app reads health data for dashboard insights.
6. Select a paid Apple Developer signing team, connect an iPhone, then build and run.
7. Grant read permission when prompted. Sync runs on launch, when the app becomes active, and when the dashboard requests it.

## Incremental sync

HealthKitSyncManager persists one HKQueryAnchor for each HealthKit sample type. The first pass imports available records. Later passes query only additions or changed samples after each saved anchor. The native bridge sends the existing version 1 daily JSON contract to index.html, so History, Trends, Progress, Health Score, recommendations, and the manual export importer remain compatible.
