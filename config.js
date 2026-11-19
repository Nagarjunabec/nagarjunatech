
/* ---- Supabase (database) ----
   Supabase dashboard > Project Settings > API
     SB_URL = "Project URL"
     SB_KEY = "anon / public" key   (never use the service_role key here)      */
const SB_URL = 'https://rlunhmwmyfxtyvnczozs.supabase.co';
const SB_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJsdW5obXdteWZ4dHl2bmN6b3pzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTE4NTcwMzcsImV4cCI6MjEwNzQzMzAzN30.cUUtWYS2R2qU8HdIAXc7VFLzTKB-rrJidmhq38P54co';

/* ---- Admin mailbox ----
   Used as the reply-to address of every e-mail and shown in the e-mail footer.  */
const ADMIN_MAIL = 'nagarjunabec2009@gmail.com';

/* ---- Names shown on the site and in e-mails ---- */
const ORG_NAME = 'Nagarjuna Tech Academy';
const DEVELOPERS = 'Gaddam Venu and T Nagarjuna';

/* ---- Android app (APK) download link, shown on the login page ---- */
const APK_URL = 'https://web2apkpro.com/download/45A882B/Nagarjuna-Tech-Academy';

/* ---- E-mail (Brevo) ----
   NO key here any more. The Brevo key is kept in Netlify > Environment variables
   (BREVO_API_KEY, BREVO_SENDER_EMAIL, BREVO_SENDER_NAME) and used only by
   netlify/functions/send-email.js, so it is never sent to the browser or to GitHub.   */

/* NOTE: on Netlify, the environment variables SB_URL, SB_KEY, ADMIN_MAIL, ORG_NAME, DEVELOPERS and APK_URL
   (if you add them) replace the values above at deploy time (scripts/build-config.js). */

/* ---- Lab programs: time-slot drop-down (edit if the periods change). The lab location is typed by the admin. ---- */
const LAB_SLOTS = ['9.00 AM to 11.30 AM', '11.30 AM to 2.00 PM', '2.00 PM to 4.30 PM'];
