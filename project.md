# Moona Project Notes

## Overview

Moona is a shopping list application focused on fast household shopping coordination. It supports bilingual Arabic/English UI, dark/light themes, user accounts, shared lists, item images, category filtering, quantity/unit details, autocomplete from a shared product catalog, and an admin area for managing global app data.

This document is intentionally implementation agnostic. It describes the product behavior, domain model, and expected user flows without prescribing how they are built or hosted.


## Technology Stack
- This is to be a cross-platform mobile-first app; flutter to be used.
- Riverpod for state management.
- appwrite to be used for backend, real-time updates, admin panel, database, auth, files storage, users management.

## Product Goals

- Let a user maintain a simple active shopping list.
- Let multiple users collaborate on the same list in near realtime.
- Make adding common products fast through autocomplete.
- Support Arabic-first usage while allowing English UI.
- Keep item cards compact enough for repeated mobile use.
- Provide admin tools for managing categories, units, universal products, and users.

## Core Concepts

- User: an account with credentials, display name, language preference, theme preference, sharing status, and owned list items.
- Shopping list: the active pending items owned by a user.
- List owner: the user whose list is being viewed or edited.
- Shared viewer: a second user connected to the owner's list.
- Universal product: a globally known product name with a stable ID, used for autocomplete and name lookup.
- List item: a product reference plus list-specific details such as quantity, unit, brand, seller, category, image, and pending status.
- Category: a global grouping with Arabic name, English name, and emoji.
- Unit: a global quantity unit with Arabic and English names.
- Admin: a privileged operator who can manage global catalogs and user records.

## Domain Model

### User

A user record should contain:

- User ID.
- Display name.
- Credential secret or password hash.
- Language preference: Arabic or English.
- Theme preference: dark or light.
- Sharing pointer for a list received from another user.
- Sharing pointer for a user currently receiving this user's list.
- Owned list items.

### List Item

A list item should contain:

- Product ID from the universal product catalog.
- Count, defaulting to `1`.
- Optional unit ID.
- Optional brand.
- Optional seller or store.
- Optional category ID.
- Optional image reference.
- Pending flag.

### Universal Product

A universal product should contain:

- Product ID.
- Product name.

Product names are shared across all users and power autocomplete but deduplicated. User lists should reference product IDs so names can be normalized and reused.

### Category

A category should contain:

- Category ID.
- Arabic display name.
- English display name.
- Emoji.

Current default categories:

- Grocery.
- Produce.
- Meats.
- Fish.
- Tools.

### Unit

A unit should contain:

- Unit ID.
- Arabic display name.
- English display name.

Current default units:

- Item.
- Piece.
- Kilogram.
- Gram.
- Liter.
- Milliliter.
- Box.
- Bag.
- Bottle.
- Can.
- Pack.
- Dozen.

## User Authentication and Preferences

The first-run experience should ask for a user ID and password.

Expected behavior:

- User ID is a phone number with country international code.
- Existing users can sign in using their password.
- Unknown user IDs create a new account automatically after verifying the phone number with OTP.
- New users default to device language, device theme, no sharing, and an empty owned list.
- Passwords or credential secrets must not be stored as plain text.
- Language and theme changes should persist to the user's profile.

Preference behavior:

- Default language is the device language.
- Arabic UI should use right-to-left layout.
- English UI should use left-to-right layout.
- The language toggle switches all visible UI labels, placeholders, messages, category names, and unit names.
- The theme toggle switches the application between dark and light appearances.

## Main Shopping List Experience

The primary screen should be the working shopping list, not a landing page.

Expected controls:

- trash icon for recently marked items.
- Sharing/settings entry.
- Logout.
- Horizontal category filter.
- Active shopping list.
- Add item action.
- Toast or lightweight status messages.

Expected empty state:

- If there are no visible pending items, show a clear empty list state.
- The empty state should encourage adding the first item without explaining the whole app.

## List Loading and Ownership

When a user opens the list:

- If the user is receiving a shared list, show the owner's active list.
- Otherwise, show the user's own active list.
- Only pending items should appear in the main list.
- The response or state should expose whether the list is shared and who owns it, so the UI can reflect sharing status if needed.

## Category Filtering

The app should load categories dynamically from the global category catalog.

Category behavior:

- Always include an "All Items" filter.
- Selecting "All Items" shows every pending item.
- Selecting a category shows only pending items in that category.
- Category filters with no pending items should be hidden, except "All Items".
- In "All Items", item cards should show the category badge when the item has a category.
- In category-specific views, the category badge can be omitted because the selected filter already provides that context.

## Product and Item Details

Each item card should be compact and scannable.

Display behavior:

- Show the uploaded image when present.
- If no image exists, show a category-based emoji placeholder.
- Show the product name prominently.
- Show count and unit when count is greater than `1` or a unit is selected.
- Show brand when present.
- Show seller or store when present.
- List should be split and sectioned by category badge in the all-items view when present.

Item details supported by add/edit forms:

- Product name.
- Important toggle.
- Category.
- Image.

Under a collabsible menu show the follwoing:
- Count which defaults to '1'.
- Unit which defaults to 'Item'.
- Brand.
- Seller.

## Adding Items

The add item flow should support:

- Product name entry with autocomplete.
- Important toggle where if active, the item will be pinned at the top of the list and showed with redish theme to grab users and viewers attention.
- Count input.
- Unit selection.
- Brand entry.
- Seller entry.
- Category selection.
- Image selection or camera capture when available on the device.

Submit behavior:

1. Validate that product name is present.
2. Store or reuse the universal product by case-insensitive product name.
3. Reject adding a duplicate pending product to the same visible list.
4. Add the item to the current list owner's list.
5. Notify all active viewers of that list.
6. Close the add flow and update the visible list.

## Editing Items

The edit flow should be reachable without cluttering each card.

Expected interactions:

- Edit icon.
- Secondary click or equivalent desktop interaction opens edit.

Edit behavior:

- Existing values are prefilled.
- The same fields as the add flow are editable.
- Image can be replaced or removed.
- A delete action is available from the edit flow.
- Saving updates all active viewers of the list.

Important identity behavior:

- If the product name changes, the item may point to a different universal product ID.
- Clients should handle an item update where the product ID changes.

## Marking Off Products

The current completion model is scratch-to-delete, not a completed-items archive.

Interaction:

1. A normal tap or click marks the card as scratched.
2. The card becomes visually muted and the product name gets a line-through treatment.
3. An Undo action appears on the card.
4. A ten-second timer starts.
5. If Undo is selected, the timer is canceled and the card returns to normal.
6. If the timer expires, the item is removed from the list and moved to the Trash list.
7. All active viewers of the list are notified that the item was removed.

Behavior note:

- The model includes a pending flag, but the active user flow removes marked-off items instead of moving them to a completed state.

## Deleting Items

Deletion can happen through:

- The mark-off timer expiring.
- The delete action in the edit flow.

Delete behavior:

- Remove the item from the current list owner's active items.
- Notify all active viewers of the list.
- Do not remove the universal product itself when deleting a list item.
- Move deleted items to Trash screen which are sorted by the item they were scrached off and the user who did the action so whoever is viewing it know who marked it off.

## Autocomplete

Autocomplete uses the shared universal product catalog.

Expected behavior:

- Enabled on product name fields in add and edit flows.
- Begins after at least two typed characters.
- Performs case-insensitive substring matching.
- Returns up to 20 suggestions.
- Allows pointer selection.
- Allows keyboard-style navigation where the platform supports it.
- Selecting a suggestion fills the product name.
- The suggestion list closes when focus leaves the field or the user cancels.


Universal catalog behavior:

- New product names are added automatically when users add items.
- Duplicate product names are avoided with case-insensitive comparison.
- Admins can also add, rename, or delete universal products.
- Give the admins tools to clean up the universal products names to find similar names.

## Sharing

Sharing is owner-based and can be done with multiple users by selecting the contact or phone number of the shared user..

Sharing fields:
- A receiving user stores which owner shared a list with them.
- An owner stores which user currently receives their list.

Share flow:

1. User opens sharing/settings.
2. Opens the phone contact list and user select contact or enters a phone number manually.
3. The app validates both users exist.
4. The app rejects sharing with oneself.
5. The target user is asked to permit sharing and then if agreed linked to the sharer's list.
6. The sharer records that the target user is receiving their list.
7. The target user is notified.
8. The target user sees and edits the owner's list.

Shared list behavior:

- Both users can add items.
- Both users can edit items.
- Both users can delete or mark off items.
- Both users should see item changes without manually refreshing.
- Both users can mark an item as important and showed as such to all targeted users.

Unlink flow:

- Either side can unlink the sharing relationship.
- If the receiver unlinks, their received-list pointer is cleared and the owner's shared-with pointer is cleared.
- If the owner unlinks, the owner's shared-with pointer is cleared and the receiver's received-list pointer is cleared.
- Both sides are notified when the relationship ends.

Sharing limitations:

- The target user must already exist.
- Sharing should not silently break another active sharing relationship; if replacing an existing link is allowed, the UI should make that explicit.

## Realtime Synchronization

The app should keep active list viewers in sync.

Events to synchronize:

- Item added.
- Item updated.
- Item deleted.
- List shared.
- List unlinked.
- Item marked as important.

Expected recipients:

- The list owner.
- Any user currently connected to the owner's list.

Expected behavior:

- A user joins their own realtime channel after login.
- A user leaves their realtime channel on logout.
- Item changes made by one participant appear for the other participant.
- Sharing and unlinking updates should refresh sharing status and visible list state.

## Images and Camera Capture

Items can include an optional image.

Expected behavior:

- Add and edit flows can attach an image.
- Devices with camera support can capture a new photo.
- Users can preview an image before saving.
- Users can remove an image from the form before saving.
- Stored images should be referenced by stable paths or IDs.
- Removing an item image reference does not necessarily delete the stored image file unless a cleanup process is added.
- To avoid storing images on a server, they should be sent as peer-to-peer and stored on the targeted user phone.

Validation:

- Accept common image formats.
- Enforce a reasonable maximum image size.
- Reject invalid uploads or unsupported media.

## Admin Features

The admin area is web-based to manage global configuration and user records.

Admin authentication:

- Admin access uses a separate privileged credential.
- There is no per-user role model in the described behavior.
- Admin credentials should be configurable and should not use insecure defaults in production.

Admin sections:

- Categories.
- Units.
- Universal products.
- Users.

Category management:

- List categories.
- Add a category with ID, Arabic name, English name, and emoji.
- Edit Arabic name, English name, and emoji.
- Delete categories.
- Category IDs should be treated as stable once created.

Unit management:

- List units.
- Add a unit with ID, Arabic name, and English name.
- Edit Arabic and English names.
- Delete units.
- Unit IDs should be treated as stable once created.

Universal product management:

- List universal products.
- Add product names.
- Rename product names.
- Delete products from the universal catalog.
- Tools to deduplicate and find similar names.

User management:

- List users with user ID, display name, item count, and sharing relationship.
- Edit display name.
- Reset password when needed.
- Delete users.

Admin caveats:

- Deleting a category does not automatically update existing items that reference that category ID.
- Deleting a unit does not automatically update existing items that reference that unit ID.
- Deleting a universal product can make list items that reference it impossible to display by name unless handled.
- Deleting a user should clean up sharing references from other users.

## Service Contract Summary

The app needs service operations for these capabilities:

- Get categories.
- Get units.
- Sign in or create a user.
- Sign out.
- Get user profile.
- Update language and theme preferences.
- Get visible pending list items for a user.
- Add list item.
- Update list item.
- Delete list item.
- Search universal products for autocomplete.
- Store item image.
- Share a list with another user.
- Unlink a shared list.
- Get sharing status.
- Admin sign in.
- Admin sign out.
- Admin create/read/update/delete categories.
- Admin create/read/update/delete units.
- Admin create/read/update/delete universal products.
- Admin read/update/delete users.

## Implementation-Agnostic Risks and Decisions

- Storage should protect against concurrent writes overwriting each other.
- Product names are global, so renaming or deleting universal products can affect many users.
- Images need lifecycle management if old uploads should be removed.
- Admin defaults and credential storage need production-grade treatment.
- Realtime behavior should be validated under multiple simultaneous users.
- Automated tests should cover item CRUD, sharing, unlinking, autocomplete, preferences, and admin catalog changes.
