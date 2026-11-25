/* ==========================================================================
   public-info.js  –  what the LOGIN page shows to everybody (before login)
   Edit this file only. Nothing here touches the database.

   PUBLIC_PEOPLE : the "Details" cards   (photo on the left, name + designation on the right)
       photo : path of a picture inside the assets folder, e.g. 'assets/nagarjuna.jpg'
               (square pictures look best; leave '' to show the initials instead)
   PUBLIC_NOTICES: the notices shown on the login page, newest first
       date  : 'YYYY-MM-DD'      title : short heading      text : the message (plain text)
   ========================================================================== */
const PUBLIC_PEOPLE = [
  { name: 'T. Nagarjuna', role: 'Admin · Developer', photo: 'assets/nagarjuna.jpg' }     // put the picture in the assets folder with this name; until then the initials show
];

const PUBLIC_NOTICES = [
  { date: '2026-11-19', title: 'Welcome to Nagarjuna Tech Academy',
    text: 'Sign in with your Reg No to see your subjects, materials, marks and the notices of every subject.' }
];
