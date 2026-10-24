# 00. What to buy

For the owners. Cadasto B.V. buys and owns every key; each one is assigned
to one person and recorded in `../../signers.json` by its serial number.

Prices from Yubico's Dutch store on 2026-10-01, including VAT.

## The YubiKey: YubiKey 5C NFC

| | |
|---|---|
| **Buy** | **YubiKey 5C NFC** (USB-C and NFC), €70.18 |
| **If a computer only has USB-A** | YubiKey 5 NFC (USB-A and NFC), €70.18 |
| **Where** | directly from Yubico (<https://www.yubico.com/nl/store/>) or an authorised Yubico reseller |

Why this model:

- It belongs to the **YubiKey 5 series**, the only series with the OpenPGP
  application that GnuPG uses to sign licences. Current keys ship with
  firmware 5.8; Ed25519 needs 5.2.3 or newer.
- It is a **removable** key. It goes in the pocket and stays out of the
  laptop, so a stolen laptop does not take the key with it.
- USB-C fits every current Mac. Licences do not use NFC; it comes at no
  extra cost and serves the person's own logins.

Do not buy:

| Product | Why not |
|---|---|
| Security Key Series (from €35.09) | FIDO only: no OpenPGP, cannot hold a signing key |
| YubiKey Bio Series (from €118.58) | FIDO only: no OpenPGP |
| YubiKey 5 Nano, 5C Nano | made to stay plugged in, so it travels with the laptop; the key should not |
| YubiKey 5Ci (€102.85) | the Lightning connector is for iPhones; nothing here needs it |
| YubiKey 5 FIPS (140-2 or 140-3, from €106.48) | FIPS certification is for government and regulated buyers that require it; the licence keys gain nothing from it |
| YubiHSM 2 (from €786.50) | a server HSM for PKI and databases; signing happens on a person's laptop |

Never buy from a marketplace (second-hand, unknown sellers): a key that was
in someone else's hands cannot be trusted with a signing key.

## How many

| For | Keys |
|---|---|
| Ruben Talstra | 1 |
| Alessandro Torrisi | 1 |
| a spare, kept new and sealed (optional) | 1 |

Two keys: €140.36. With the spare: €210.54. The spare saves the wait for a
delivery when a key is lost (`05-lost-key.md`); it holds no key until it is
needed.

## When the keys arrive

1. Check that the packaging was sealed.
2. Give each owner their key. Each owner then follows `02-yubikey.md` on
   their own Mac: the app checks the key, creates the master key on it, and
   records its serial number in `../../signers.json`.
