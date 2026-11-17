// Hoppscotch bootstrap for Railway (run by boot.sh with the backend's own node_modules on the path).
//   node seed.js pre   -> mark onboarding complete before the backend first populates InfraConfig
//   node seed.js post  -> seed the administrator and the infra token
// Every statement is idempotent; the tokens are the template variables, so a changed variable rotates the credential.
const crypto = require("crypto")
const { Client } = require(process.env.PG_MODULE)

const uid = () => "c" + crypto.randomBytes(12).toString("hex")

async function main() {
  const phase = process.argv[2]
  const db = new Client({ connectionString: process.env.DATABASE_URL })
  await db.connect()
  try {
    if (phase === "pre") {
      // A non-empty provider list is what the backend reads as "onboarding completed", which closes the public
      // POST /v1/onboarding/config endpoint that otherwise lets the first visitor choose the auth providers.
      await db.query(
        `INSERT INTO "InfraConfig"(id, name, value, "updatedOn") VALUES ($1, 'VITE_ALLOWED_AUTH_PROVIDERS', 'EMAIL', now())
         ON CONFLICT (name) DO NOTHING`, [uid()])
    } else if (phase === "post") {
      const email = process.env.HOPPSCOTCH_ADMIN_EMAIL || "admin@hoppscotch.local"
      const u = await db.query(
        `INSERT INTO "User"(uid, "displayName", email, "isAdmin") VALUES ($1, 'Administrator', $2, true)
         ON CONFLICT (email) DO UPDATE SET "isAdmin" = true RETURNING uid`, [uid(), email])
      const adminUid = u.rows[0].uid
      await db.query(`DELETE FROM "InfraToken" WHERE label = 'railway-template' AND token <> $1`, [process.env.HOPPSCOTCH_INFRA_TOKEN])
      await db.query(
        `INSERT INTO "InfraToken"(id, "creatorUid", label, token) VALUES ($1, $2, 'railway-template', $3)
         ON CONFLICT (token) DO NOTHING`, [uid(), adminUid, process.env.HOPPSCOTCH_INFRA_TOKEN])
    } else if (phase === "count") {
      const r = await db.query(`SELECT count(*)::int AS n FROM "InfraConfig"`)
      console.log(r.rows[0].n)
    } else {
      throw new Error("usage: seed.js pre|post|count")
    }
  } finally {
    await db.end()
  }
}
main().catch((e) => { console.error("hoppscotch seed:", e.message); process.exit(1) })
