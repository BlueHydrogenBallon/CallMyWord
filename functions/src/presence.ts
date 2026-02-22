import { onDocumentUpdated } from "firebase-functions/v2/firestore";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { getFirestore, Timestamp } from "firebase-admin/firestore";

const db = getFirestore();

// Users are considered offline if no heartbeat for 2 minutes
const PRESENCE_TIMEOUT_MS = 2 * 60 * 1000;

// ═══════════════════════════════════════════════════════════════
// ON USER PRESENCE CHANGE
// ═══════════════════════════════════════════════════════════════

/**
 * When a user's online status changes, propagate to their friends
 */
export const onUserPresenceChange = onDocumentUpdated(
  "users/{userId}",
  async (event) => {
    const beforeData = event.data?.before.data();
    const afterData = event.data?.after.data();

    if (!beforeData || !afterData) return;

    // Check if online status or lastActiveAt changed
    const onlineChanged = beforeData.isOnline !== afterData.isOnline;
    const lastActiveChanged =
      beforeData.lastActiveAt?.toMillis() !== afterData.lastActiveAt?.toMillis();

    if (!onlineChanged && !lastActiveChanged) return;

    const userId = event.params.userId;

    console.log(
      `User ${userId} presence changed: online=${afterData.isOnline}`
    );

    // For now, we'll rely on the friends collection being updated
    // when friends are fetched (denormalized data refresh)
    // A more scalable solution would use a reverse index

    // Update all friend entries for this user
    const batch = db.batch();
    let updateCount = 0;

    // Find all users who have this userId in their friends subcollection
    // We need to iterate through users - this is not ideal for scale
    // but works for a small user base

    // Get all friend relationships where this user is the friend
    const usersSnapshot = await db.collection("users").get();

    for (const userDoc of usersSnapshot.docs) {
      if (userDoc.id === userId) continue;

      const friendRef = userDoc.ref.collection("friends").doc(userId);
      const friendDoc = await friendRef.get();

      if (friendDoc.exists) {
        batch.update(friendRef, {
          isOnline: afterData.isOnline,
          lastActiveAt: afterData.lastActiveAt || null,
        });
        updateCount++;

        // Commit in batches of 500
        if (updateCount >= 500) {
          await batch.commit();
          updateCount = 0;
        }
      }
    }

    if (updateCount > 0) {
      await batch.commit();
    }

    console.log(`Updated ${updateCount} friend entries for user ${userId}`);
  }
);

// ═══════════════════════════════════════════════════════════════
// CLEANUP STALE PRESENCE (Scheduled)
// ═══════════════════════════════════════════════════════════════

/**
 * Mark users as offline if their heartbeat is stale
 */
export const cleanupStalePresence = onSchedule("every 1 minutes", async () => {
  const staleThreshold = Timestamp.fromMillis(Date.now() - PRESENCE_TIMEOUT_MS);

  // Find users who are marked online but have stale heartbeats
  const staleUsers = await db
    .collection("users")
    .where("isOnline", "==", true)
    .where("lastHeartbeat", "<", staleThreshold)
    .limit(100)
    .get();

  if (staleUsers.empty) {
    console.log("No stale presence found");
    return;
  }

  const batch = db.batch();

  for (const doc of staleUsers.docs) {
    batch.update(doc.ref, {
      isOnline: false,
    });
  }

  await batch.commit();
  console.log(`Marked ${staleUsers.size} users as offline due to stale heartbeat`);
});
