# CoKeep

Track and split maintenance work on co-owned property (cabins, shared homes, and generic objects).

## Stack

| Layer | Technology |
|-------|------------|
| Backend | Node.js, Express, TypeScript, Prisma |
| Database | PostgreSQL 16 |
| iOS | Native SwiftUI (iOS 17+) |
| Localization | English (default), Norwegian (`nb`) |

## Features (v1)

- **Objects** — create property objects from Cabin or Generic templates, optional image
- **To-do lists** — multiple named lists; items with schedule (one-off or recurring), assignee, done section, due-date sort
- **Work logs** — start/end time entries per item; total duration on list, full log on detail
- **Costs** — amount + optional receipt photo; optional link to a to-do item
- **Reports** — spendings & work: totals, per-user breakdown, preset/custom periods, list + charts
- **Users & invites** — register, invite by phone / contacts; Messages compose for new users, push for existing
- **Membership** — leave object anytime; creator can remove members
- **Notifications** — due soon (7 days) and overdue push alerts
- **Profile** — name, email, avatar; forgot-password email reset deep link
- **Launch splash** — optional Markdown announcement / force-update gate (admin UI at `/admin`)

## Quick start

### 1. Database

```bash
docker compose up -d
```

### 2. Backend

```bash
cd backend
cp .env.example .env
npm install
npx prisma migrate dev
npm run seed   # optional demo data
npm run dev
```

API listens on `http://localhost:3000`. Health: `GET /health`.

### 3. iOS

1. Open `ios/CoKeep/CoKeep.xcodeproj` in Xcode on a Mac.
2. Set your team / bundle ID under Signing.
3. Update `APIClient.baseURL` if needed (simulator → `http://localhost:3000`).
4. Run on a simulator or device (iOS 17+).

## Environment variables

See `backend/.env.example` for JWT secrets, SMTP, APNs, and admin login placeholders.

## Project layout

```
backend/          Express API + Prisma schema
ios/CoKeep/       Native SwiftUI app
docker-compose.yml
```

## API overview

| Area | Prefix |
|------|--------|
| Auth | `/api/auth` |
| Users / profile | `/api/users` |
| Objects & members | `/api/objects` |
| Invites | `/api/invites` |
| Todo lists / items | `/api/objects/:id/todo-lists` |
| Work logs | `/api/todo-items/:id/logs` |
| Costs | `/api/objects/:id/costs` |
| Reports | `/api/objects/:id/reports` |
| Uploads | `/api/uploads` |
| App launch config | `/api/app` |
| Admin UI | `/admin` |

## Notes

- Invites return an `inviteUrl` for the iOS app to open in Messages; APNs push is used for existing users. Email uses SMTP when configured (otherwise console).
- Password reset and invite deep links use `cokeep://` URL schemes (configure Associated Domains for production App Store links).
