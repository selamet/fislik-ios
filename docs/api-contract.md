# Fişlik API contract (iOS client)

Source of truth: `fislik-api` (FastAPI). Summary derived from fislik-api@4a7ce4f and fislik-web@4bea512.

## Basics
- Base URL: `https://fislik-api.selamet.dev` (web: `https://fislik.selamet.dev`)
- IDs: 32-char hex. Period: `YYYY-MM`. Money: JSON strings (Decimal). Dates `YYYY-MM-DD`; datetimes ISO-8601 UTC.
- Auth: `Authorization: Bearer <jwt>` from `access_token` in AuthOut. 7-day JWT, no refresh; on 401 → logout. Disable cookie storage.
- Errors: `{"detail": string}`; 422 validation `{"detail": [..]}`; 429 `{"error": string}`.
- Turkish details safe to show: "Bu ay muhasebeciniz tarafından kapatıldı." / "Bağlı muhasebeciniz yok" / "Bu ay zaten gönderildi" / "Aylık analiz limiti doldu" / "Dosya çok büyük (en fazla 15 MB)."

## Auth
| Method | Path | Body | Response |
|---|---|---|---|
| POST | /auth/register | {email,password(min8),full_name,role: client\|accountant, invite_token?} | 201 AuthOut {id,email,full_name,role,impersonated,access_token}; 409 email taken |
| POST | /auth/login | {email,password} | AuthOut; 401 bad creds; 403 Google-only account |
| POST | /auth/oauth/google | {credential} | {status: logged_in\|needs_role, user?, registration_token?} |
| POST | /auth/oauth/register | {registration_token, role} | 201 AuthOut |
| GET | /auth/me | – | {id,email,full_name,role,impersonated} |
| DELETE | /auth/me | – | 204 |
| POST | /auth/change-password | {current_password,new_password} | 204; 400 wrong current |
| POST | /auth/password-reset/request | {email} | 204 always |
| POST | /auth/password-reset/confirm | {token,new_password} | 204; 400 invalid |

## Receipts
ReceiptOut `{id, period, created_at, image_url (presigned GET, 1h), content_type, processed, open_issue: {id,message,author_name,created_at}|null, extraction: ExtractionOut|null (null = queued, no credit), uploaded_by: str|null}`

ExtractionOut `{status: pending|done|failed, merchant_name, merchant_legal_name, receipt_date, total_amount, vat_total, vat_breakdown:[{rate,amount}], doc_type: fis|fatura|unknown, merchant_tax_id, merchant_tax_id_type: vkn|tckn, merchant_tax_office, receipt_number, payment_method: nakit|kredi_karti|bilinmiyor, expense_category: yemek|market|yakit|ulasim|konaklama|ofis|teknoloji|iletisim|saglik|diger, edited}`. VAT rates {0,1,8,10,18,20}. Poll every 5s while any pending.

Upload: `POST /receipts/uploads {content_type, period?, client_id?}` → `{receipt_id, object_key, upload_url}` (PUT, 600s, exact Content-Type, no auth) → `POST /receipts/{id}/complete {size_bytes?}` → ReceiptOut. 15 MB max (413). Images → JPEG ≤2000px ~1MB.

| Method | Path | Notes |
|---|---|---|
| GET | /receipts?period= | ReceiptOut[] (client). No detail endpoint. |
| PATCH | /receipts/{id} | {period} move month |
| DELETE | /receipts/{id} | 204 |
| GET | /receipts/summary?period=&client_id= | {receipt_count, analyzed_count, total_amount, vat_total, vat_by_rate, payment_method_totals, category_totals} |
| PATCH | /receipts/{id}/extraction | partial ExtractionOut fields → edited=true |
| POST | /receipts/{id}/extraction/retry | free retry for failed/never analyzed |
| POST | /receipts/{id}/extraction/reanalyze | costs 1 credit |
| GET | /receipts/period-lock?period=&client_id= | {locked, locked_at} (404 → not locked) |
| GET | /receipts/submission?period= | {last_sent_at, can_send, active_receipt_count, has_accountant} |
| POST | /receipts/submit | {period} |

## Issues
- `POST /clients/{client_id}/receipts/{receipt_id}/issues {message}` (accountant) → IssueOut; 409 already open
- `POST /issues/{id}/resolve` (client) → 204

## Grants
GrantOut `{id, status: pending|active|revoked, invited_email, direction: incoming|outgoing, counterpart_name, counterpart_email, invited_role}`
- `POST /grants {email}`; `GET /grants`; `POST /grants/{id}/accept`; `POST /grants/{id}/decline`; `DELETE /grants/{id}`
- `GET /grants/invite/{token}` (public) → {invited_email, inviter_name, inviter_role, invited_role}; `POST /grants/invite/{token}/accept`

## Accountant
- `GET /clients?period=` → [{client_id, full_name, receipt_count, unprocessed_count, last_upload_at}]
- `GET /clients/{id}/receipts?period=`; `GET /clients/{id}/company`
- `POST|DELETE /clients/{id}/receipts/{rid}/processed`; `POST /clients/{id}/receipts/processed {period}`; `DELETE /clients/{id}/receipts/processed?period=`
- `GET /clients/{id}/receipts.zip?period=`
- `POST|DELETE /clients/{id}/periods/{period}/lock`
- Excel/CSV/PDF export is built client-side (columns: Tarih, Satıcı, VKN/TCKN, Vergi Dairesi, Fiş No, Belge Türü, Toplam, KDV Toplam, KDV %1, KDV %10, KDV %20, Ödeme Yöntemi, Kategori, Analiz, İşlendi).

## Company
`GET /company` (404 = not set) / `PUT /company {full_name, trade_name?, tax_office, tax_number(10), national_id?(11), business_address, tax_type?, activity_code?, activity_name?, started_on?}`

## Credits
`GET /credits/me` → {limit, used, remaining, unlimited}

## Notifications
`GET /notifications?limit&offset` → {unread_count, items:[{id,type,payload,read,created_at}]}; `POST /notifications/read {ids|null}`.
Types: grant_invite, invite_accepted, invite_declined, issue_opened, issue_resolved, receipts_submitted, receipts_processed, period_locked.

## Gaps (backend work needed)
- No push / device token endpoints.
- No Sign in with Apple.
- Google ID token audience is web-only.
- No notification preferences.
- No apple-app-site-association on fislik.selamet.dev (universal links for /davet, /sifre-sifirla).
