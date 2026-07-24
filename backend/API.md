# CoKeep API reference

Base URL: `http://localhost:3000`  
Auth: `Authorization: Bearer <token>` on protected routes.

## Auth

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| POST | `/api/auth/register` | no | Register (min password length 5). Auto-joins pending phone invites. |
| POST | `/api/auth/login` | no | Login with email/password |
| GET | `/api/auth/me` | yes | Current user |
| POST | `/api/auth/forgot-password` | no | Email reset link (`cokeep://reset-password?token=…`) |
| POST | `/api/auth/reset-password` | no | Body: `{ token, password }` |

## Users

| Method | Path | Description |
|--------|------|-------------|
| PATCH | `/api/users/me` | Update name, email, avatarUrl |
| POST | `/api/users/device-token` | Register APNs device token |
| GET | `/api/users/notifications` | In-app notifications |
| POST | `/api/users/notifications/:id/read` | Mark read |

## Objects

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/objects` | List objects for current user |
| POST | `/api/objects` | Create (`name`, `template`: `CABIN`\|`GENERIC`, optional `imageUrl`) |
| GET | `/api/objects/:id` | Detail + members + lists |
| PATCH | `/api/objects/:id` | Owner updates name/image |
| POST | `/api/objects/:id/leave` | Leave object |
| DELETE | `/api/objects/:id/members/:userId` | Owner removes member |

## Invites

| Method | Path | Description |
|--------|------|-------------|
| POST | `/api/invites/objects/:objectId/invites` | Invite by phone (`phone`, `countryCode`) |
| GET | `/api/invites/pending` | Pending invites for current user |
| POST | `/api/invites/:inviteId/respond` | `{ accept: true\|false }` |
| GET | `/api/invites/objects/:objectId/invites` | Owner lists invites |

## Todos

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/objects/:id/todo-lists` | Lists with open (due-first) + done sections |
| POST | `/api/objects/:id/todo-lists` | Create list |
| PATCH | `/api/todo-lists/:listId` | Rename |
| DELETE | `/api/todo-lists/:listId` | Delete |
| POST | `/api/todo-lists/:listId/items` | Create item |
| GET | `/api/todo-items/:itemId` | Detail + work logs |
| PATCH | `/api/todo-items/:itemId` | Update / assign / mark done |
| DELETE | `/api/todo-items/:itemId` | Delete |
| POST | `/api/todo-items/:itemId/logs` | Log work `{ startedAt, endedAt, note? }` |

## Costs & reports

| Method | Path | Description |
|--------|------|-------------|
| GET/POST | `/api/objects/:id/costs` | List / create costs |
| GET/PATCH/DELETE | `/api/costs/:costId` | Get / edit / delete own cost |
| GET | `/api/objects/:id/reports/spendings` | `?period=week\|month\|quarter\|year\|all\|custom&from=&to=` |
| GET | `/api/objects/:id/reports/work` | Same period query; minutes + per-user + chart |

## Uploads

| Method | Path | Description |
|--------|------|-------------|
| POST | `/api/uploads` | multipart `file` image → `{ url }` |
