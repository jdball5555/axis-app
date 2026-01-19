const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");
const moment = require("moment-timezone");

admin.initializeApp();
const db = admin.firestore();

// =========================================================
// 🎨 HELPER: MINIMALIST STATUS
// =========================================================
function getStatusIcon(days) {
  if (days <= 3) return "🔴"; // Critical
  if (days <= 7) return "🟠"; // Warning
  return ""; 
}

// =========================================================
// 📅 HELPER: DATE PARSING
// =========================================================
function parseFlutterDate(dateStr) {
  if (!dateStr) return null;
  if (typeof dateStr.toDate === 'function') return moment(dateStr.toDate());
  if (typeof dateStr === 'string') {
    const cleanStr = dateStr.trim();
    const formats = [
      "YYYY-MM-DD HH:mm:ss.SSS", "YYYY-MM-DD HH:mm:ss",
      moment.ISO_8601, "M/D/YYYY H:mm", "M/D/YYYY h:mm A",
      "MM/DD/YYYY HH:mm", "D/M/YYYY H:mm"
    ];
    let m = moment(cleanStr, formats);
    if (m.isValid()) return m;
    m = moment(Date.parse(cleanStr));
    if (m.isValid()) return m;
  }
  return null;
}

// =========================================================
// 🧠 SHARED LOGIC: REPORT GENERATION
// =========================================================
async function generateUserReport(uid) {
  try {
    const now = moment().tz("America/Chicago");
    const currentHour = now.hour();

    const userRef = db.collection("users").doc(uid);
    const userDoc = await userRef.get();
    if (!userDoc.exists) return;

    const userData = userDoc.data();
    const households = userData.joinedHouseholds || [];
    const fcmToken = userData.fcmToken;

    if (!fcmToken || households.length === 0) return;

    // --- 1. DETERMINE ACTIONS ---
    const checkRunout = (userData.runoutHour === currentHour && userData.runoutEnabled !== false);
    const checkUsage = (userData.usageHour === currentHour && userData.usageEnabled !== false);
    const checkReport = (userData.reportHour === currentHour && userData.reportEnabled === true);

    let sendReportNow = false;
    if (checkReport) {
      const lastSent = userData.lastReportSent ? userData.lastReportSent.toDate() : null;
      const freqDays = userData.reportFrequency || 1;
      if (!lastSent) {
        sendReportNow = true;
      } else {
        const daysDiff = moment(now).diff(moment(lastSent), "days");
        if (daysDiff >= freqDays) sendReportNow = true;
      }
    }

    if (!checkRunout && !checkUsage && !sendReportNow) return;

    // --- 2. GATHER DATA ---
    const reportGroups = {}; 
    const alertMessages = [];
    const reportIds = userData.reportInventoryIds || [];

    for (const householdId of households) {
      const [hhDoc, invSnap, logsSnap] = await Promise.all([
        db.collection("households").doc(householdId).get(),
        db.collection(`households/${householdId}/inventory`).get(),
        db.collection(`households/${householdId}/activity_log`).orderBy("timestamp", "desc").get(),
      ]);

      if (!hhDoc.exists) continue;
      
      const hhData = hhDoc.data();
      const inventoryName = (hhData.name || "INVENTORY").toUpperCase();
      const customThresholds = hhData.runoutThresholds || [7, 3, 0];

      const includeInReport = sendReportNow && (reportIds.length === 0 || reportIds.includes(householdId));
      const enableRunoutForHH = checkRunout && hhData.runoutEnabled !== false;
      const enableUsageForHH = checkUsage && hhData.usageEnabled !== false;

      const rawLogs = logsSnap.docs.map(d => d.data());
      const aggregates = {};

      // 3. SUM QUANTITIES
      invSnap.docs.forEach((doc) => {
        const item = doc.data();
        if (item.type === 'Room') return;
        const nameKey = (item.name || "").trim().toLowerCase();
        let qty = Number(item.quantity);
        if (isNaN(qty)) qty = 0;

        if (!aggregates[nameKey]) {
          aggregates[nameKey] = {
            realName: item.name, 
            totalQty: 0,
            totalDailyRate: 0.0,
            newestDate: null
          };
        }
        aggregates[nameKey].totalQty += qty;
      });

      // 4. CALCULATE RATES
      invSnap.docs.forEach((doc) => {
        const item = doc.data();
        if (item.type === 'Room') return;
        const nameKey = (item.name || "").trim().toLowerCase();
        let itemRoom = (item.roomLocation || "").trim().toLowerCase();
        if (itemRoom === "" || itemRoom === "n/a") itemRoom = "unknown";

        const specificLogs = rawLogs.filter(log => {
          let logName = (log.item || "").toString().trim().toLowerCase();
          if (logName.includes("_")) logName = logName.split("_")[0];
          let logRoom = (log.room || "").toString().trim().toLowerCase();
          if (logRoom === "" || logRoom === "n/a") logRoom = "unknown";
          
          const nameMatch = (logName === nameKey);
          let roomMatch = false;
          if (itemRoom === "unknown") roomMatch = (logRoom === "unknown");
          else roomMatch = (logRoom === itemRoom || logRoom === "unknown");

          return nameMatch && roomMatch && (log.action || "").toString().toUpperCase().includes("USED");
        });

        if (specificLogs.length >= 2) {
          const validDates = specificLogs
            .map(l => parseFlutterDate(l.timestamp))
            .filter(d => d !== null && d.isValid())
            .sort((a, b) => b.valueOf() - a.valueOf());

          if (validDates.length >= 2) {
            const newest = validDates[0];
            const oldest = validDates[validDates.length - 1];

            if (!aggregates[nameKey].newestDate || newest.isAfter(aggregates[nameKey].newestDate)) {
              aggregates[nameKey].newestDate = newest;
            }

            const totalDaysSpan = newest.diff(oldest, "days") || 1;
            const intervals = validDates.length - 1;
            const avgDaysPerUse = totalDaysSpan / (intervals < 1 ? 1 : intervals);

            if (avgDaysPerUse > 0) {
              aggregates[nameKey].totalDailyRate += (1.0 / avgDaysPerUse);
            }
          }
        }
      });

      // 5. GENERATE LINES
      const inventoryLines = [];

      Object.values(aggregates).forEach((agg) => {
        if (agg.totalDailyRate > 0 && agg.newestDate) {
          const stockDurationDays = (agg.totalQty + 1) / agg.totalDailyRate;
          const daysSinceLastUse = now.diff(agg.newestDate, 'days');
          const daysLeft = Math.round(stockDurationDays - daysSinceLastUse);
          const icon = getStatusIcon(daysLeft);

          // ALERTS
          if (enableRunoutForHH && agg.totalQty > 0) {
             if (customThresholds.includes(daysLeft)) {
                alertMessages.push(`${agg.realName}: ${daysLeft} days left ${icon}`);
             }
          }

          if (enableUsageForHH && agg.totalQty > 0) {
             const daysPerItem = Math.round(1.0 / agg.totalDailyRate);
             if (daysSinceLastUse >= daysPerItem) {
                alertMessages.push(`Use ${agg.realName}`);
             }
          }

          // REPORT LINES
          if (includeInReport) {
            if (daysLeft < 20) {
              let line = `• ${agg.realName}: ${daysLeft}d`;
              if (icon) line += ` ${icon}`;
              inventoryLines.push(line);
            }
          }
        }
      });

      if (inventoryLines.length > 0) {
        reportGroups[inventoryName] = inventoryLines;
      }
    }

    // --- SEND ALERTS ---
    if (alertMessages.length > 0) {
      const alertBody = alertMessages.join("\n");
      await admin.messaging().send({
        notification: { title: "Inventory Alerts", body: alertBody },
        android: { notification: { icon: "notification_icon", color: "#FF5252" } },
        data: { type: "inventory_alert" },
        token: fcmToken,
      });
    }

    // --- SEND REPORT ---
    if (sendReportNow) {
      let reportBody = "";
      const inventoryNames = Object.keys(reportGroups);

      if (inventoryNames.length > 0) {
         inventoryNames.forEach((invName, index) => {
           if (index > 0) reportBody += "\n";
           const lines = reportGroups[invName];
           reportBody += `${invName}\n`; 
           lines.forEach(line => {
             reportBody += `${line}\n`;
           });
         });
      } else {
         reportBody = "Everything is well stocked.";
      }

      if (reportBody.length > 0) {
        if (reportBody.length > 3500) reportBody = reportBody.substring(0, 3500) + "...";
        
        await admin.messaging().send({
          notification: { title: "Inventory Report", body: reportBody },
          android: { notification: { icon: "notification_icon", color: "#00C897" } },
          data: { type: "inventory_report" },
          token: fcmToken,
        });
      }

      await userRef.update({ lastReportSent: admin.firestore.FieldValue.serverTimestamp() });
    }

  } catch (error) {
    console.error("Error:", error);
  }
}

// =========================================================
// EXPORTS
// =========================================================

exports.sendInviteNotification = functions.firestore
  .document("invitations/{inviteId}")
  .onCreate(async (snap, context) => {
    try {
      const invite = snap.data();
      const email = invite.email;
      const userSnapshot = await db.collection("users").where("email", "==", email).limit(1).get();
      if (userSnapshot.empty) return;
      const userDoc = userSnapshot.docs[0];
      const fcmToken = userDoc.data().fcmToken;
      if (!fcmToken) return;
      const payload = {
        notification: { title: "New Invitation", body: `${invite.inviterName} invited you to join ${invite.householdName}.` },
        android: { notification: { icon: "notification_icon", color: "#00C897", tag: "invite_tag" } },
        data: { type: "invite" },
        token: fcmToken,
      };
      return admin.messaging().send(payload);
    } catch (e) { console.error(e); }
  });

exports.hourlyInventoryCheck = functions.pubsub
  .schedule("0 * * * *")
  .timeZone("America/Chicago")
  .onRun(async (context) => {
    const now = moment().tz("America/Chicago");
    const currentHour = now.hour();
    const [runoutUsers, usageUsers, reportUsers] = await Promise.all([
      db.collection("users").where("runoutHour", "==", currentHour).get(),
      db.collection("users").where("usageHour", "==", currentHour).get(),
      db.collection("users").where("reportHour", "==", currentHour).get(),
    ]);
    const usersToCheck = new Set();
    runoutUsers.forEach((doc) => usersToCheck.add(doc.id));
    usageUsers.forEach((doc) => usersToCheck.add(doc.id));
    reportUsers.forEach((doc) => usersToCheck.add(doc.id));
    if (usersToCheck.size === 0) return null;
    await Promise.all(Array.from(usersToCheck).map((uid) => generateUserReport(uid)));
    return null;
  });

exports.onMemberRemoved = functions.firestore
  .document("households/{householdId}")
  .onUpdate(async (change, context) => {
    try {
      const afterData = change.after.data();
      const removedMemberIds = (change.before.data().members || []).filter(uid => !(change.after.data().members || []).includes(uid));
      if (removedMemberIds.length === 0) return null;
      let removerName = "an admin";
      if (context.auth && context.auth.uid) {
        const removerDoc = await db.collection("users").doc(context.auth.uid).get();
        if (removerDoc.exists) removerName = removerDoc.data().displayName || "an admin";
      }
      await Promise.all(removedMemberIds.map(async (uid) => {
        const userDoc = await db.collection("users").doc(uid).get();
        if (userDoc.exists && userDoc.data().fcmToken) {
          await admin.messaging().send({
            notification: { title: "Access Revoked", body: `You have been removed from "${afterData.name}" by ${removerName}.` },
            android: { notification: { icon: "notification_icon", color: "#00C897", tag: "removal_alert" } },
            data: { type: "removal" },
            token: userDoc.data().fcmToken,
          });
        }
      }));
    } catch (e) { console.error(e); }
    return null;
  });