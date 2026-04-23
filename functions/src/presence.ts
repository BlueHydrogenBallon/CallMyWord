import { onValueWritten } from "firebase-functions/v2/database";
import { getFirestore, FieldValue } from "firebase-admin/firestore";

const db = getFirestore();

// ═══════════════════════════════════════════════════════════════
// ON USER PRESENCE CHANGE  (RTDB trigger)
// ═══════════════════════════════════════════════════════════════

/**
 * Triggered when `/status/{userId}` changes in Realtime Database.
 *
 * The client writes `{ online: true }` on connect and registers an
 * `onDisconnect()` handler that writes `{ online: false }`.  This function
 * mirrors the change to Firestore:
 *   1. Updates the user's own doc (`isOnline`, `lastActiveAt`).
 *   2. Propagates the new status to every friend's subcollection entry
 *      using the `friendOf` reverse index (O(1) reads + O(friends) writes).
 *
 * Because the trigger only fires on actual value changes (not periodic
 * heartbeats), Cloud Function invocations are minimised.
 *
 * The scheduled `cleanupStalePresence` function is no longer needed — RTDB
 * `onDisconnect()` handles tab close, crash, and network loss server-side.
 */
export const onUserPresenceChange = onValueWritten(
  "status/{userId}",
  async (event) => {
    const userId = event.params.userId;

    const afterData = event.data.after.val();
    if (!afterData) return;

    const isOnline: boolean = afterData.online === true;

    // Read the previous value to avoid unnecessary propagation.
    // Only skip if both are offline (offline→offline is redundant).
    // Always propagate when online=true, even if RTDB already had online=true,
    // because the friend subcollection entries may be stale from a missed disconnect.
    const beforeData = event.data.before.val();
    const wasOnline: boolean = beforeData?.online === true;

    if (!isOnline && !wasOnline) return;

    console.log(
      `User ${userId} presence changed: online=${isOnline}`
    );

    // Update the user's own Firestore doc.
    // Clients watch this doc directly for each friend's online status,
    // so no propagation to friend subcollections is needed.
    const userRef = db.collection("users").doc(userId);
    const updateData: Record<string, unknown> = {
      isOnline,
      lastActiveAt: FieldValue.serverTimestamp(),
    };
    // Clear the legacy lastHeartbeat field if present
    if (!isOnline) {
      updateData.lastHeartbeat = FieldValue.delete();
    }
    await userRef.update(updateData);

    console.log(`Updated user ${userId} isOnline=${isOnline}`);
  }
);
