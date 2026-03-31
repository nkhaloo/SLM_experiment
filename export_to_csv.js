// Run with: node export_to_csv.js

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
const NUM_TRIALS = 20;

// ===============================
// Export Function
// ===============================
async function exportData() {
  console.log("Reading data from Firestore...");

  const usersSnap = await db.collection("users").get();
  const rows = [];

  for (const userDoc of usersSnap.docs) {
    const u = userDoc.data();
    const userId = u.userId || userDoc.id;

    const row = { user_id: userId };

    // ---------------------------
    // Reading task
    // ---------------------------
    row.passage_reading = u.passageReadingURL || "";

    // ---------------------------
    // Practice trial
    // ---------------------------
    row.practice_participant_recording = u.practiceParticipantRecordingURL || "";
    row.practice_model_response       = u.practiceModelResponseURL || "";

    // ---------------------------
    // Experimental trials (1–20)
    // ---------------------------
    const convSnap = await userDoc.ref
      .collection("conversation")
      .orderBy("trialNumber")
      .get();

    const trials = [];
    convSnap.forEach(doc => trials.push(doc.data()));

    for (let n = 1; n <= NUM_TRIALS; n++) {
      const t = trials.find(t => t.trialNumber === n) || {};
      const p = `trial_${String(n).padStart(2, "0")}`;
      row[`${p}_participant_recording`] = t.userAudioURL          || "";
      row[`${p}_model_response`]        = t.replyAudioURL         || "";
      row[`${p}_domain`]                = t.domain                || "";
      row[`${p}_type`]                  = t.questionType          || "";
      row[`${p}_accuracy`]              = t.perceivedAccuracy      || "";
      row[`${p}_reliance`]              = t.perceivedRisk          || "";
      row[`${p}_validation`]            = t.followupValidation     || "";
    }

    // ---------------------------
    // System impression (part 1)
    // ---------------------------
    const si = u.systemImpression || {};
    row.si_knowledgeable  = si.knowledgeable   || "";
    row.si_best_interest  = si.bestInterest     || "";
    row.si_honest         = si.honest           || "";
    row.si_unbiased       = si.unbiased         || "";
    row.si_trustworthiness= si.trustworthiness  || "";
    row.si_collaborator   = si.collaborator     || "";

    // ---------------------------
    // System impression (part 2 — anthropomorphism)
    // ---------------------------
    const anth = u.anthropomorphism || {};
    row.anth_authenticity = anth.authenticity || "";
    row.anth_humanism     = anth.humanism     || "";
    row.anth_awareness    = anth.awareness    || "";
    row.anth_realism      = anth.realism      || "";
    row.anth_competence   = anth.competence   || "";
    row.anth_total_score  = anth.totalScore  ?? "";

    // ---------------------------
    // Demographics
    // ---------------------------
    const d = u.demographics || {};
    row.demo_age               = d.age !== undefined ? Number(d.age) : "";
    row.demo_ethnicity         = Array.isArray(d.ethnicity)
                                   ? d.ethnicity.join("; ")
                                   : (d.ethnicity || "");
    row.demo_ethnicity_other   = d.ethnicityOther   || "";
    row.demo_grew_up_location  = d.grewUpLocation   || "";
    row.demo_first_language    = d.firstLanguage    || "";
    row.demo_other_languages   = d.otherLanguages   || "";
    row.demo_gender            = d.gender           || "";
    row.demo_speech_disorder   = d.speechDisorder   || "";
    row.demo_speech_description= d.speechDescription|| "";
    row.demo_neurodivergent    = d.neurodivergent   || "";
    row.demo_neuro_description = d.neuroDescription || "";
    row.demo_technologies_used = Array.isArray(d.technologiesUsed)
                                   ? d.technologiesUsed.join("; ")
                                   : (d.technologiesUsed || "");
    row.demo_ai_use_frequency  = d.aiUseFrequency   || "";
    row.demo_ai_attitude       = d.aiAttitude       || "";

    // ---------------------------
    // Final open-ended feedback
    // ---------------------------
    const fb = u.openEndedFeedback || {};
    row.feedback_system_experience = fb.systemExperience   || "";
    row.feedback_additional        = fb.additionalFeedback || "";

    rows.push(row);
  }

  if (!rows.length) {
    console.log("No data found.");
    return;
  }

  // ===============================
  // Build ordered field list
  // ===============================
  const fields = [
    "user_id",
    "passage_reading",
    "practice_participant_recording",
    "practice_model_response",
  ];

  for (let n = 1; n <= NUM_TRIALS; n++) {
    const p = `trial_${String(n).padStart(2, "0")}`;
    fields.push(
      `${p}_participant_recording`,
      `${p}_model_response`,
      `${p}_domain`,
      `${p}_type`,
      `${p}_accuracy`,
      `${p}_reliance`,
      `${p}_validation`
    );
  }

  fields.push(
    "si_knowledgeable",
    "si_best_interest",
    "si_honest",
    "si_unbiased",
    "si_trustworthiness",
    "si_collaborator",
    "anth_authenticity",
    "anth_humanism",
    "anth_awareness",
    "anth_realism",
    "anth_competence",
    "anth_total_score",
    "demo_age",
    "demo_ethnicity",
    "demo_ethnicity_other",
    "demo_grew_up_location",
    "demo_first_language",
    "demo_other_languages",
    "demo_gender",
    "demo_speech_disorder",
    "demo_speech_description",
    "demo_neurodivergent",
    "demo_neuro_description",
    "demo_technologies_used",
    "demo_ai_use_frequency",
    "demo_ai_attitude",
    "feedback_system_experience",
    "feedback_additional"
  );

  // ===============================
  // Write CSV
  // ===============================
  const parser = new Parser({ fields });
  const csv = parser.parse(rows);

  fs.writeFileSync("./participants_data.csv", csv);
  console.log("Saved: participants_data.csv");
}

// ===============================
exportData().then(() => {
  console.log("Export complete.");
  process.exit();
});
