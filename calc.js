/* R24 and R26 Calculator – ONE set of formulas for both regulations (unchanged from the original calculator) */
document.getElementById('calcform').addEventListener('submit', function (e) { e.preventDefault(); calculate(); });

function calculate() {
  const aat1 = parseFloat(document.getElementById('aat1').value);
  const aat2 = parseFloat(document.getElementById('aat2').value);
  const mid1 = parseFloat(document.getElementById('mid1').value);
  const mid2 = parseFloat(document.getElementById('mid2').value);
  const per = parseFloat(document.getElementById('per').value);
  const result = document.getElementById('result');

  // Validate input
  if (isNaN(aat1) || aat1 < 0 || aat1 > 10 ||
      isNaN(aat2) || aat2 < 0 || aat2 > 10 ||
      isNaN(mid1) || mid1 < 0 || mid1 > 30 ||
      isNaN(mid2) || mid2 < 0 || mid2 > 30 ||
      isNaN(per) || per < 1 || per > 100) {
    result.innerHTML = "❌ Please enter valid marks and attendance.";
    return;
  }

  // AAT and Mid Calculation
  const avgAAT = (aat1 + aat2) / 2;
  const aatMarks = (avgAAT / 10) * 15;

  const bestMid = Math.max(mid1, mid2);
  const otherMid = Math.min(mid1, mid2);
  const midWeight = (bestMid * 0.75 + otherMid * 0.25);
  const midWeighted = (midWeight / 30) * 20;

  // Attendance Bonus and Condonation Logic
  let attendanceBonus = 0;
  let condonationMsg = "";
  let notQualified = false;

  if (per >= 90) attendanceBonus = 5;
  else if (per >= 85) attendanceBonus = 4;
  else if (per >= 80) attendanceBonus = 3;
  else if (per >= 75) attendanceBonus = 2;
  else if (per >= 65) {
    attendanceBonus = 0;
    condonationMsg = "<br><span style='color:orange;'>⚠️ Condonation Fee ₹500 Required</span>";
  } else {
    attendanceBonus = 0;
    notQualified = true;
  }

  const totalMarks = aatMarks + midWeighted + attendanceBonus;

  // Build Result Output (layout only: the marks above are calculated exactly as before)
  let output = `<div class="total">Total Internal Marks (out of 40)<strong>${totalMarks.toFixed(2)}</strong></div>`;
  output += `<table class="parts"><tr><td>AAT (out of 15)</td><td>${aatMarks.toFixed(2)}</td></tr>` +
            `<tr><td>Mid (out of 20)</td><td>${midWeighted.toFixed(2)}</td></tr>` +
            `<tr><td>Attendance (out of 5)</td><td>${attendanceBonus}</td></tr></table>`;

  if (notQualified) {
    output += "<span style='color:red; font-weight:bold;'>❌ Not Qualified: Attendance below 65%</span>";
  } else if (totalMarks >= 21) {
    output += "<span style='color:green; font-weight:bold;'>✅ Qualified: You can write the semester exam</span>";
  } else {
    output += "<span style='color:red; font-weight:bold;'>❌ Not Qualified: Marks below 21</span>";
  }

  output += condonationMsg;
  result.innerHTML = output;
}
