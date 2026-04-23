import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore, FieldValue, Timestamp } from "firebase-admin/firestore";
import {
  AddFriendByCodeRequest,
  AcceptFriendRequestRequest,
  DeclineFriendRequestRequest,
  RemoveFriendRequest,
  BlockFriendRequest,
  GenerateInviteCodeResponse,
  Friend,
} from "./types";

const db = getFirestore();

// ═══════════════════════════════════════════════════════════════
// GENERATE INVITE CODE
// ═══════════════════════════════════════════════════════════════

/**
 * Generate a unique 6-character invite code for the user
 */
export const generateInviteCode = onCall(async (request): Promise<GenerateInviteCodeResponse> => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be signed in");
  }

  const userId = request.auth.uid;
  const userRef = db.collection("users").doc(userId);
  const userDoc = await userRef.get();

  if (!userDoc.exists) {
    throw new HttpsError("not-found", "User profile not found");
  }

  // Check if user already has an invite code
  const existingCode = userDoc.data()?.inviteCode;
  if (existingCode) {
    return { inviteCode: existingCode };
  }

  // Generate a unique code
  let inviteCode = generateRandomCode();
  let attempts = 0;
  const maxAttempts = 10;

  while (attempts < maxAttempts) {
    const existing = await db
      .collection("users")
      .where("inviteCode", "==", inviteCode)
      .limit(1)
      .get();

    if (existing.empty) {
      break;
    }
    inviteCode = generateRandomCode();
    attempts++;
  }

  if (attempts >= maxAttempts) {
    throw new HttpsError("internal", "Could not generate unique invite code");
  }

  // Save the invite code
  await userRef.update({
    inviteCode: inviteCode,
    updatedAt: FieldValue.serverTimestamp(),
  });

  return { inviteCode };
});

/**
 * Generate a random 6-character alphanumeric code
 */
function generateRandomCode(): string {
  const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // Exclude similar chars like 0/O, 1/I
  let code = "";
  for (let i = 0; i < 6; i++) {
    code += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  return code;
}

// ═══════════════════════════════════════════════════════════════
// ADD FRIEND BY CODE
// ═══════════════════════════════════════════════════════════════

/**
 * Add a friend using their invite code
 * Creates bidirectional friend entries with appropriate statuses
 */
export const addFriendByCode = onCall<AddFriendByCodeRequest>(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be signed in");
  }

  const userId = request.auth.uid;
  const inviteCode = request.data.inviteCode?.toUpperCase().trim();

  if (!inviteCode || inviteCode.length !== 6) {
    throw new HttpsError("invalid-argument", "Invalid invite code format");
  }

  // Find the user with this invite code
  const targetUserSnapshot = await db
    .collection("users")
    .where("inviteCode", "==", inviteCode)
    .limit(1)
    .get();

  if (targetUserSnapshot.empty) {
    throw new HttpsError("not-found", "No user found with this invite code");
  }

  const targetUserDoc = targetUserSnapshot.docs[0];
  const targetUserId = targetUserDoc.id;
  const targetUserData = targetUserDoc.data();

  // Can't add yourself
  if (targetUserId === userId) {
    throw new HttpsError("invalid-argument", "Cannot add yourself as a friend");
  }

  // Get current user's data
  const currentUserDoc = await db.collection("users").doc(userId).get();
  if (!currentUserDoc.exists) {
    throw new HttpsError("not-found", "Your profile not found");
  }
  const currentUserData = currentUserDoc.data()!;

  // Check if already friends
  const existingFriend = await db
    .collection("users")
    .doc(userId)
    .collection("friends")
    .doc(targetUserId)
    .get();

  if (existingFriend.exists) {
    const status = existingFriend.data()?.status;
    if (status === "accepted") {
      throw new HttpsError("already-exists", "Already friends with this user");
    }
    if (status === "pending") {
      throw new HttpsError("already-exists", "Friend request already pending");
    }
    if (status === "blocked") {
      throw new HttpsError("failed-precondition", "Cannot add this user");
    }
  }

  const now = Timestamp.now();

  // Create friend entries for both users
  const batch = db.batch();

  // Entry for current user (sender) - accepted from their side
  const senderFriendRef = db
    .collection("users")
    .doc(userId)
    .collection("friends")
    .doc(targetUserId);

  const senderFriendData: Friend = {
    displayName: targetUserData.displayName || "Unknown",
    avatarUrl: targetUserData.avatarUrl || null,
    status: "accepted",
    isOnline: targetUserData.isOnline || false,
    lastActiveAt: targetUserData.lastActiveAt || null,
    createdAt: now,
    addedBy: userId,
  };
  batch.set(senderFriendRef, senderFriendData);

  // Entry for target user (receiver) - pending until they accept
  const receiverFriendRef = db
    .collection("users")
    .doc(targetUserId)
    .collection("friends")
    .doc(userId);

  const receiverFriendData: Friend = {
    displayName: currentUserData.displayName || "Unknown",
    avatarUrl: currentUserData.avatarUrl || null,
    status: "pending",
    isOnline: currentUserData.isOnline || false,
    lastActiveAt: currentUserData.lastActiveAt || null,
    createdAt: now,
    addedBy: userId,
  };
  batch.set(receiverFriendRef, receiverFriendData);

  // Maintain reverse index: friendOf[X] = users who have X in their friends subcollection.
  // userId has targetUserId in their friends → add userId to targetUser.friendOf
  // targetUserId has userId in their friends → add targetUserId to currentUser.friendOf
  batch.update(db.collection("users").doc(targetUserId), {
    friendOf: FieldValue.arrayUnion(userId),
  });
  batch.update(db.collection("users").doc(userId), {
    friendOf: FieldValue.arrayUnion(targetUserId),
  });

  await batch.commit();

  return {
    success: true,
    friendId: targetUserId,
    friendName: targetUserData.displayName,
  };
});

// ═══════════════════════════════════════════════════════════════
// ACCEPT FRIEND REQUEST
// ═══════════════════════════════════════════════════════════════

export const acceptFriendRequest = onCall<AcceptFriendRequestRequest>(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be signed in");
  }

  const userId = request.auth.uid;
  const friendUserId = request.data.friendUserId;

  if (!friendUserId) {
    throw new HttpsError("invalid-argument", "Missing friendUserId");
  }

  // Get the friend entry
  const friendRef = db
    .collection("users")
    .doc(userId)
    .collection("friends")
    .doc(friendUserId);

  const friendDoc = await friendRef.get();

  if (!friendDoc.exists) {
    throw new HttpsError("not-found", "Friend request not found");
  }

  const friendData = friendDoc.data() as Friend;

  if (friendData.status !== "pending") {
    throw new HttpsError("failed-precondition", "No pending request from this user");
  }

  // Only the receiver can accept (the one who didn't initiate)
  if (friendData.addedBy === userId) {
    throw new HttpsError("failed-precondition", "Cannot accept your own request");
  }

  // Fetch both users' current online status so friend docs are up-to-date
  const [currentUserDoc, friendUserDoc] = await Promise.all([
    db.collection("users").doc(userId).get(),
    db.collection("users").doc(friendUserId).get(),
  ]);
  const currentUserData = currentUserDoc.data();
  const friendUserData = friendUserDoc.data();

  // Update both friend entries to accepted with fresh online status
  const batch = db.batch();

  batch.update(friendRef, {
    status: "accepted",
    isOnline: friendUserData?.isOnline ?? false,
    lastActiveAt: friendUserData?.lastActiveAt ?? null,
  });

  const otherFriendRef = db
    .collection("users")
    .doc(friendUserId)
    .collection("friends")
    .doc(userId);

  batch.update(otherFriendRef, {
    status: "accepted",
    isOnline: currentUserData?.isOnline ?? false,
    lastActiveAt: currentUserData?.lastActiveAt ?? null,
  });

  await batch.commit();

  return { success: true };
});

// ═══════════════════════════════════════════════════════════════
// DECLINE FRIEND REQUEST
// ═══════════════════════════════════════════════════════════════

export const declineFriendRequest = onCall<DeclineFriendRequestRequest>(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be signed in");
  }

  const userId = request.auth.uid;
  const friendUserId = request.data.friendUserId;

  if (!friendUserId) {
    throw new HttpsError("invalid-argument", "Missing friendUserId");
  }

  // Delete both friend entries
  const batch = db.batch();

  batch.delete(
    db.collection("users").doc(userId).collection("friends").doc(friendUserId)
  );

  batch.delete(
    db.collection("users").doc(friendUserId).collection("friends").doc(userId)
  );

  // Remove from reverse index
  batch.update(db.collection("users").doc(friendUserId), {
    friendOf: FieldValue.arrayRemove(userId),
  });
  batch.update(db.collection("users").doc(userId), {
    friendOf: FieldValue.arrayRemove(friendUserId),
  });

  await batch.commit();

  return { success: true };
});

// ═══════════════════════════════════════════════════════════════
// REMOVE FRIEND
// ═══════════════════════════════════════════════════════════════

export const removeFriend = onCall<RemoveFriendRequest>(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be signed in");
  }

  const userId = request.auth.uid;
  const friendUserId = request.data.friendUserId;

  if (!friendUserId) {
    throw new HttpsError("invalid-argument", "Missing friendUserId");
  }

  // Delete both friend entries
  const batch = db.batch();

  batch.delete(
    db.collection("users").doc(userId).collection("friends").doc(friendUserId)
  );

  batch.delete(
    db.collection("users").doc(friendUserId).collection("friends").doc(userId)
  );

  // Remove from reverse index
  batch.update(db.collection("users").doc(friendUserId), {
    friendOf: FieldValue.arrayRemove(userId),
  });
  batch.update(db.collection("users").doc(userId), {
    friendOf: FieldValue.arrayRemove(friendUserId),
  });

  await batch.commit();

  return { success: true };
});

// ═══════════════════════════════════════════════════════════════
// BLOCK FRIEND
// ═══════════════════════════════════════════════════════════════

export const blockFriend = onCall<BlockFriendRequest>(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be signed in");
  }

  const userId = request.auth.uid;
  const friendUserId = request.data.friendUserId;

  if (!friendUserId) {
    throw new HttpsError("invalid-argument", "Missing friendUserId");
  }

  const batch = db.batch();

  // Update current user's entry to blocked
  const myFriendRef = db
    .collection("users")
    .doc(userId)
    .collection("friends")
    .doc(friendUserId);

  batch.set(myFriendRef, { status: "blocked" }, { merge: true });

  // Remove the other user's entry for this user
  batch.delete(
    db.collection("users").doc(friendUserId).collection("friends").doc(userId)
  );

  // /users/{friendUserId}/friends/{userId} is deleted, so remove userId from friendUserId.friendOf
  batch.update(db.collection("users").doc(friendUserId), {
    friendOf: FieldValue.arrayRemove(userId),
  });

  await batch.commit();

  return { success: true };
});
