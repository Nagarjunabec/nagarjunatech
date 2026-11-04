# Deploy on Netlify (GitHub -> Netlify)

## A. Run it on your computer
1. Install Node.js (LTS) from nodejs.org.
2. Copy `.env.example` to `.env` and fill the values (the file is ignored by git).
3. In PowerShell inside the project folder:
   `npx netlify-cli dev`
   Open the address it prints (http://localhost:8888). Pages AND e-mail work, exactly like the live site.
   (VS Code "Live Server" also opens the pages, but e-mail will not work there because there is no function.)

## B. Push to GitHub (fresh history, no old key)
    cd C:\Users\venur\Documents\nagarjuna-tech-academy
    Remove-Item -Recurse -Force .git
    git init
    git add .
    git commit -m "v38 netlify"
    git branch -M main
    git remote add origin https://github.com/<your-user>/nagarjuna-tech-academy.git
    git push -u origin main --force

## C. Netlify
1. app.netlify.com -> Add new project -> Import an existing project -> GitHub -> choose `nagarjuna-tech-academy`, branch `main`.
2. Build settings are read from `netlify.toml`  (build command `node scripts/build-config.js`, publish directory `.`, functions `netlify/functions`). Leave the boxes as they are.
3. BEFORE the first deploy (or then "Trigger deploy"), Project configuration -> Environment variables -> add:

| Name | Value | Mark "Contains secret values" |
|---|---|---|
| BREVO_API_KEY | your NEW Brevo key | YES |
| BREVO_SENDER_EMAIL | verified sender e-mail | no |
| BREVO_SENDER_NAME | Nagarjuna Tech Academy | no |
| SB_URL | Supabase Project URL | no |
| SB_KEY | Supabase anon (public) key | no |
| ADMIN_MAIL | admin mailbox (optional) | no |

4. Brevo -> Security -> Authorised IPs: switch OFF (Netlify has no fixed IP).
5. Deploy -> open the site -> login as admin -> Email -> "Send test e-mail".
