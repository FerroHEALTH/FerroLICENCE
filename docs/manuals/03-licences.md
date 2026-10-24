# 03. Issue, renew and revoke licences

For the owners, each with their own YubiKey (`02-yubikey.md`). A few
minutes per licence, of which about one is GitHub's.

Everything starts in **Customers**, where the app opens. The list begins
with **Needs Attention**: licences ending within 60 days, and licences that
ended in the last 90 days with nothing after them. Each row starts with a
symbol for its state:

| Symbol | Means |
|---|---|
| green tick | valid |
| orange triangle | ends within 60 days |
| grey minus | ended |
| grey clock | starts later |
| red octagon | revoked |

The toolbar's key symbol is green when the YubiKey plugged in holds your
trusted key. When it is grey, **New Licence** is disabled and its tooltip
says why.

## A new customer

1. Click **New Licence** in the toolbar (File › New Licence…, ⌘N). The
   sheet shows three steps: Draft, Check, Sign.
2. **Draft.** Type the customer's legal name exactly as in the signed
   agreement. **Starts** is today and **Ends** one year later, the day
   before the anniversary. **Type** is Commercial unless this is a free
   (non-commercial) licence. **Contract** is your own reference to the
   agreement; it stays in the register and is never put in the licence.
   Click **Continue**.
3. **Check Before Signing.** Read every line: a signed licence can never be
   changed. **Exact text the YubiKey signs** opens the text itself. Click
   **Sign with YubiKey**, or **Back** to change the draft.
4. **Sign with Your YubiKey.** A pinentry window asks for your PIN. Then
   the YubiKey's light blinks; touch it. The app checks the signed licence
   with FerroEHR's checks before anything leaves your Mac. **Cancel** stops
   the signing and nothing is kept.
5. **Recording the Licence.** The app runs the Register check, opens a pull
   request on GitHub and merges it into `main`. Each line ticks when it is
   done; the pull request's number links to GitHub. This takes a few
   seconds. You can click **Close**; a notification says when the licence
   is recorded.
6. **Licence Recorded.** Click **Download to Downloads** (below), or **Later**.

If the Register check refuses the licence, nothing is opened on GitHub and
the sheet says why. The signed file never reached the register, so it must not reach
the customer. Send the message to the other owner.

## Renewing

On a customer that needs attention, the orange banner has **Renew…**
(also Licence › Renew… in the menu bar). The draft is filled in: the same
customer and type, starting the day after the current licence ends, for a
year, linked to the licence it renews. Usually you only add the contract
reference, then go through Check and Sign as above.

The old licence stays in the register; identifiers minted under it remain
in the customer's data. A contract that ends gets no renewal. One that ends
early gets a revocation (below).

## Getting the licence to the customer

**Download to Downloads** sits on the Licence Recorded sheet and in the
toolbar of every customer's current licence. It saves `licence.asc` in your
Downloads folder at once, without asking where; the symbol turns into a
tick to say it is there. An earlier copy is never overwritten: the next one
is named `… 2.licence.asc`. Attach that file to a mail to the customer. The
file is not secret.

**Copy Setup Instructions** (on the same sheet, and in the licence's More
menu) copies the text their IT needs (`../ferroehr-integration.md` §7);
paste it into the mail. **Save Licence File…** in More asks where to save,
for any other folder.

The file in the register is the one the customer gets. If they lose it,
open the customer and download it again.

## Revoke

When a contract ends early or a licence is misused.

1. Open the customer and click **Revoke…** under the current licence.
2. **Reason:** say why in a sentence (the contract clause, the termination
   letter).
3. **Stops from:** the day it no longer counts.
4. Type `REVOKE`. The **Revoke** button stays disabled until the word is
   there.
5. Click **Revoke**. The app records it like a licence: a pull request with
   `revocation.json` after the Register check, then the merge.

The installation keeps running: an offline licence cannot be switched off,
and FerroEHR never degrades (`../design.md` §1). From then on Check a File
shows the revocation for that file, and Attest Data counts identifiers
minted on or after that day. Do not issue the renewal.

## Mistakes

A licence is in the register once its pull request is merged, and the
register is append-only: never edit or delete a licence. Issue a corrected
licence and send it. If the wrong one was already sent, revoke it from
today with the reason "replaced by the corrected licence".

## Two owners at the same time

Licence ids are UUIDv7 and every licence has its own folder, so two
licences recorded at the same moment never touch the same file.

## History

**Activity** in the sidebar lists every licence, revocation and key change
as a sentence, grouped by day, with who recorded it and its pull request.
Clicking a licence row opens its customer. The filter narrows to licences,
revocations or keys.

## The free licence every build embeds

The register's "Everyone, under the Business Source License 1.1" licence is
the non-commercial grant every FerroEHR build carries. It is issued again
only when the key that signed it is retired: click **New Licence**, name it
exactly `Everyone, under the Business Source License 1.1`, choose Free, and
set **Ends** to 31 December 2099. Then paste its `licence.asc` into
FerroEHR's `licence` module as `EMBEDDED_TOKEN`, with both trusted
`keys/*.asc` as `ANCHOR_CERTIFICATES`. FerroEHR's unit test
`the_embedded_token_verifies_as_non_commercial_when_present` proves the pair
before the change can merge.

## Something fails

| What the app says | What to do |
|---|---|
| Plug in your YubiKey. | plug it in; the toolbar's key turns green within ten seconds |
| The YubiKey plugged in does not hold your trusted key. | plug in your own YubiKey, or finish `02-yubikey.md` |
| Your GitHub account is not a key holder in signers.json | only owners sign; your row needs your GitHub login (`02-yubikey.md`) |
| Wrong PIN. Each wrong PIN uses one of the card's three tries. | sign again with the right PIN; Settings › Signing shows the tries left |
| The signed licence does not pass FerroEHR's checks. Nothing was recorded. | the app refused its own output. Send the message to the other owner |
| No PIN window appears | in Terminal: `gpgconf --kill gpg-agent`, then sign again |
| Not synced: no connection | Check and Attest keep working from the offline copy; recording needs a connection |
