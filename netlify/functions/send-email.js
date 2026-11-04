/* ==========================================================================
   Netlify Function  /.netlify/functions/send-email
   The Brevo API key lives ONLY here, in Netlify > Environment variables. The browser never sees it.

   Environment variables (Netlify > Project configuration > Environment variables):
     BREVO_API_KEY        Brevo API key (xkeysib-...)                 [mark as secret]
     BREVO_SENDER_EMAIL   verified sender in Brevo > Senders
     BREVO_SENDER_NAME    name shown as the sender
     BREVO_REPLY_TO       (optional) reply-to address, default = sender e-mail
     SB_URL, SB_KEY       Supabase URL + anon key (used to check that the caller is the admin)

   Only a logged-in ADMIN of the portal may use this function.
   ========================================================================== */
const BREVO = 'https://api.brevo.com/v3';
const MAX_BCC = 99;
const MAIL_RE = /^\S+@\S+\.\S+$/;

const reply = (statusCode, obj) => ({
  statusCode,
  headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' },
  body: JSON.stringify(obj),
});

async function isAdmin(token) {
  const base = (process.env.SB_URL || '').replace(/\/$/, ''), key = process.env.SB_KEY || '';
  if (!base || !key || !token) return false;
  try {
    const r = await fetch(base + '/rest/v1/rpc/profile_get', {
      method: 'POST',
      headers: { apikey: key, Authorization: 'Bearer ' + key, 'Content-Type': 'application/json' },
      body: JSON.stringify({ t: token }),
    });
    if (!r.ok) return false;
    const p = await r.json().catch(() => null);
    return !!p && p.role === 'admin';
  } catch (e) { return false; }
}

const cleanList = (a, seen = new Set()) => (Array.isArray(a) ? a : [])
  .filter(r => r && MAIL_RE.test(r.email || '') && !seen.has(r.email.toLowerCase()) && seen.add(r.email.toLowerCase()))
  .map(r => ({ email: r.email, name: r.name || undefined }));

exports.handler = async (event) => {
  if (event.httpMethod !== 'POST') return reply(405, { message: 'Use POST' });

  const apiKey = (process.env.BREVO_API_KEY || '').trim();
  const senderEmail = (process.env.BREVO_SENDER_EMAIL || '').trim();
  const senderName = (process.env.BREVO_SENDER_NAME || '').trim() || 'Portal';
  if (!apiKey) return reply(500, { message: 'BREVO_API_KEY is not set in Netlify environment variables' });
  if (!senderEmail) return reply(500, { message: 'BREVO_SENDER_EMAIL is not set in Netlify environment variables' });
  if (!process.env.SB_URL || !process.env.SB_KEY) return reply(500, { message: 'SB_URL / SB_KEY are not set in Netlify environment variables' });

  let b;
  try { b = JSON.parse(event.body || '{}'); } catch (e) { return reply(400, { message: 'Bad request' }); }
  if (!(await isAdmin(b.token))) return reply(401, { message: 'Not allowed: log in as admin' });
  if (b.action !== 'send') return reply(400, { message: 'Unknown action' });

  const replyTo = (process.env.BREVO_REPLY_TO || senderEmail).trim();
  const bcc = cleanList(b.bcc);
  if (bcc.length > MAX_BCC) return reply(400, { message: 'Too many recipients in one request (max ' + MAX_BCC + ')' });
  const to = cleanList(b.to);                                   // visible "To" (the admin)
  const subject = String(b.subject || '').slice(0, 300);
  if (!subject || !b.htmlContent) return reply(400, { message: 'Subject and message are required' });

  const payload = {
    sender: { name: senderName, email: senderEmail },
    replyTo: { email: replyTo, name: senderName },
    to: to.length ? to : [{ email: replyTo, name: senderName }],
    subject,
    htmlContent: String(b.htmlContent),
    textContent: String(b.textContent || ''),
    tags: ['portal'],
  };
  if (bcc.length) payload.bcc = bcc;

  try {
    const r = await fetch(BREVO + '/smtp/email', {
      method: 'POST',
      headers: { accept: 'application/json', 'content-type': 'application/json', 'api-key': apiKey },
      body: JSON.stringify(payload),
    });
    const j = await r.json().catch(() => ({}));
    if (!r.ok) {
      const hint = r.status === 401 ? ' (Brevo > Security > Authorised IPs must be OFF, because Netlify has no fixed IP; or the API key is wrong)' : '';
      return reply(r.status, { message: (j.message || 'Brevo error ' + r.status) + hint });
    }
    return reply(200, { messageIds: j.messageIds || (j.messageId ? [j.messageId] : []) });
  } catch (e) { return reply(502, { message: 'Could not reach Brevo: ' + (e.message || 'network error') }); }
};
