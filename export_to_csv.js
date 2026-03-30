import fs from "fs";
import { Parser } from "json2csv";
import admin from "firebase-admin";
import serviceAccount from "./service_account_key.json" with { type: "json" };

// ===============================
// Firebase Admin Init
// ===============================
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  projectId: serviceAccount.project_id,
  storageBucket: "slm-experiment-dev.firebasestorage.app",
});


const db = admin.firestore();

// ===============================
// Export Function
// ===============================
async function exportData() {
  console.log("📦 Reading data from Firestore...");

  const usersSnap = await db.collection("users").get();
  const rows = [];

  for (const userDoc of usersSnap.docs) {
    const userData = userDoc.data();

    const userId = userData.userId || userDoc.id;
    const condition = userData.condition || "";
    const createdAt =
      userData.createdAt?.toDate?.() || userData.createdAt || "";

    const trialOrder = JSON.stringify(userData.trialOrder || []);

    const passageReadingURL = userData.passageReadingURL || "";

    const anthropomorphism = userData.anthropomorphism || {};
    const anthropomorphismTotal =
      anthropomorphism.totalScore ?? "";

    // ===============================
    // Per-trial data
    // ===============================
    const convSnap = await userDoc.ref
      .collection("conversation")
      .get();

    // If no trials, still write one row
    if (convSnap.empty) {
      rows.push({
        userId,
        condition,
        createdAt,

        trialIndex: "",
        trialNumber: "",
        domain: "",
        context: "",
        questionType: "",
        questionText: "",

        userAudioURL: "",
        replyAudioURL: "",
        modelText: "",

        perceivedAccuracy: "",
        perceivedRisk: "",
        followupValidation: "",
        timestamp: "",

        passageReadingURL,
        anthropomorphismTotal,
        trialOrder,
      });
      continue;
    }

    // One row per trial
    convSnap.forEach(doc => {
      const t = doc.data();

      rows.push({
        userId,
        condition,
        createdAt,

        trialIndex: t.trialIndex ?? "",
        trialNumber: t.trialNumber ?? "",
        domain: t.domain ?? "",
        context: t.context ?? "",
        questionType: t.questionType ?? "",
        questionText: t.questionText ?? "",

        userAudioURL: t.userAudioURL ?? "",
        replyAudioURL: t.replyAudioURL ?? "",
        modelText: t.modelText ?? "",

        perceivedAccuracy: t.perceivedAccuracy ?? "",
        perceivedRisk: t.perceivedRisk ?? "",
        followupValidation: t.followupValidation ?? "",
        timestamp: t.timestamp?.toDate?.() || t.timestamp || "",

        passageReadingURL,
        anthropomorphismTotal,
        trialOrder,
      });
    });
  }

  if (!rows.length) {
    console.log("⚠️ No data found.");
    return;
  }

  // ===============================
  // CSV Export
  // ===============================
  const fields = [
    "userId",
    "condition",
    "createdAt",

    "trialIndex",
    "trialNumber",
    "domain",
    "context",
    "questionType",
    "questionText",

    "userAudioURL",
    "replyAudioURL",
    "modelText",

    "perceivedAccuracy",
    "perceivedRisk",
    "followupValidation",
    "timestamp",

    "passageReadingURL",
    "anthropomorphismTotal",
    "trialOrder",
  ];

  const parser = new Parser({ fields });
  const csv = parser.parse(rows);

  fs.writeFileSync("./participants_data.csv", csv);
  console.log("✅ Saved locally: participants_data.csv");

  const bucket = admin.storage().bucket();
  await bucket.file("exports/participants_data.csv").save(csv, {
    contentType: "text/csv",
  });

  console.log("✅ Uploaded to Storage: exports/participants_data.csv");
}

// ===============================
exportData().then(() => {
  console.log("🎉 Export complete.");
  process.exit();
});
