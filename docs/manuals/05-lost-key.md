# 05. A lost key, or an owner who leaves

For the owners. When a YubiKey is lost, stolen or broken, when its Admin PIN
is blocked, or when its holder leaves Cadasto B.V. About fifteen minutes,
plus a FerroEHR release when the set of trusted keys changes.

## What is at stake

Each master key exists only on its YubiKey. Losing the card loses the key
for good; nothing can recover it. Two things are always true:

- **Every licence the key already signed stays valid.** The licence carries
  the key's public certificate, and FerroEHR keeps trusting that key until a
  release drops it from `keys/`.
- **The other owner keeps issuing** with their own key, without waiting for
  anything.

What differs is whether someone else could use the card. A thief needs the
PIN and a touch of the key for every signature, and three wrong PINs block
it. Whether that is enough is your call.

## In the app

1. Open **Keys** in the sidebar and choose **Change Keys › Stop Using a
   Key…** (also in the Keys menu).
2. **Key:** choose the key.
3. **Why:** choose one of the three answers below. A key that already
   signs nothing new can only be retired.
4. Type the word the sheet asks for, `HANDOVER`, `LOST` or `RETIRE`, and
   click the button beside **Cancel**.

The app records the change like a licence: a pull request, the Register
check, the merge. Either owner can record it.

**Lost, and nobody else has the PIN.** The card is broken, was destroyed,
or is lost somewhere nobody will pick it up with the PIN. Type `LOST` and
click **Mark as Lost**. The key stays trusted, so the licences it signed
need nothing; `signers.json` marks it `lost`. The holder sets up a new
YubiKey (`02-yubikey.md`), which is a new key trusted from FerroEHR's next
release. The other owner issues in the meantime.

**Someone else may have it and its PIN, or its holder left.** Type `RETIRE`
and click **Retire Key**. The certificate moves to `keys/retired/` and
`signers.json` marks it `retired`. Then:

1. Find the licences it signed that are still valid: in **Customers**, each
   licence's **Signed by** names its key's holder.
2. For each one, issue a replacement with the remaining key
   (`03-licences.md`): the same customer, the same last day, today as the
   first day. Send the new files before the FerroEHR release.
3. FerroEHR's next release embeds the new `keys/` set. From that release a
   licence signed by the retired key is refused. If the free licence every
   build embeds was signed by that key, issue it again in the same release
   (`03-licences.md` §The free licence every build embeds).

Until that release the register exposes forgeries: their licence ids are not
in it, and Attest Data never attributes them to a real grant.

The app refuses to retire the last trusted key; set up another YubiKey
first.

If the holder leaves on good terms and hands the YubiKey back, nothing needs
retiring: wipe the card (`02-yubikey.md` §A card to wipe) and mark the key
handed over, as below. Their licences stay valid until they end; renewals
are signed by the remaining owner or the successor.

## Handing over to someone else

A key cannot be moved: it was created on its YubiKey and cannot be copied
off. Handing over the YubiKey itself would sign the successor's licences in
the old holder's name. So a handover is a new key and a changed status:

1. The successor sets up their own YubiKey (`02-yubikey.md`) and saves
   their key for an owner.
2. The owner who is leaving, or the other owner, trusts it with **Trust a
   New Key…**.
3. The leaving owner's key is marked handed over: **Stop Using a Key…**,
   **Handed over to someone with their own key**, type `HANDOVER`. It
   stays trusted, so every licence it signed stays valid until it ends, and
   it signs nothing new; Keys shows it as Handed Over. Wipe the card. The
   app refuses this while no other key is in use, so trust the successor's
   key first.

Only if someone else may still hold the old YubiKey and its PIN is it
retired instead, with the reissue that needs.

## Admin PIN blocked

Three wrong Admin PINs block the card for good. Wipe it
(`02-yubikey.md` §A card to wipe); its key is gone. Then mark the key lost.
The wiped card can go through `02-yubikey.md` again and receive a new key.

## Statuses in Keys and `signers.json`

| In Keys | In `signers.json` | Meaning |
|---|---|---|
| In Use | `active` | the key signs licences |
| Handed Over | `handed-over` | its holder handed over to someone with their own key; still trusted, so its licences stay valid; it signs nothing new |
| Lost | `lost` | the card is gone or wiped; the key is still trusted so its licences stay valid |
| Retired | `retired` | the key is no longer trusted; its certificate is in `keys/retired/` |

A row is never deleted. The app's Register check refuses a change that removes a
row, renames a holder or brings a retired key back.
