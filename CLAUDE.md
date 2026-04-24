# Ravon Courier — Delivery Driver App

## What This Is

iOS app for delivery couriers to accept and complete food delivery orders in Tajikistan. Couriers see available orders, accept them, navigate to the restaurant, pick up food, deliver to the customer. UI is in Russian.

## Tech Stack

- Swift, SwiftUI, MVVM
- Supabase (via RavonCore package)
- MapKit / CoreLocation (for navigation and live location)
- iOS 17+
- SPM for dependencies

## Shared Package

This app depends on `RavonCore` (github.com/mmarufov/ravon-core) which provides:
- All data models (Order, OrderItem, Restaurant, Address, Profile, OrderStatus, etc.)
- AuthService (sign in/up/out, session management)
- SupabaseService (database queries, order status updates)
- Theme (colors, buttons, text fields)

Import with `import RavonCore`. Call `RavonCore.configure(supabaseURL:supabaseAnonKey:)` at app launch.

## What To Build

### MVP Features (Priority Order)

1. **Auth**: Login screen for courier accounts (role: courier)
2. **Go Online/Offline**: Toggle to start/stop receiving delivery offers
3. **Available Orders**: List of orders with status `ready` that need a courier
4. **Accept Delivery**: Tap to claim an order (sets courierId + status to `assigned`)
5. **Active Delivery View**:
   - Show restaurant address + navigate there
   - "Picked Up" button (status → `delivering`)
   - Show customer address + navigate there
   - "Delivered" button (status → `delivered`)
6. **Earnings**: Simple daily/weekly earnings summary
7. **Profile**: Courier info, vehicle type

### Suggested Architecture
