> **Draft for Graham's review. Not published.** This replaces the text at https://inmyshoebox.com/privacy. It is written from how the app and the relay in this repository actually behave (relay/app/README.md has the numbers). It is not legal advice. Before publishing: read it against the app once, set the effective date, and consider a short lawyer review for the California and EU sections. Remove this box when it goes live.

# Shoebox privacy policy

Effective: [date to be set when published]

Shoebox is made and run by Graham DeNoyer, an individual. Questions: support@inmyshoebox.com.

## The short version

- Your posts stay on your phone. There is no account.
- No ads, no tracking, no analytics, no tools from other companies inside the app.
- Three things pass through our server: link previews, stock pictures, and (only if you turn it on) your Shoebox email address.
- Forwarded email is sealed on our server to a key only your phone holds, so we cannot read it. It waits up to 7 days, until your phone collects it. Then it is deleted.
- Delete everything in Settings removes what we hold for you.

## What stays on your phone

Everything you keep: links, notes, photos, files, your reasons, the dates read from them, your settings, and the line you write in Settings about who your mail is about. Reading a photo (the words in it, the faces and subject for framing) and writing a post from an email happen on your phone with Apple's on-device tools. Shoebox does not send your words or photos to an AI service.

Shoebox saves a backup of your posts every day to the Shoebox folder in Files on your phone and, if you use iCloud Drive, to your iCloud Drive. Those files belong to you and are covered by Apple's terms for iCloud. A backup does not include the secret key that ties your phone to its email address. That key is kept in your Keychain and, if you use iCloud Keychain, comes to your new phone that way. Keep your backups private.

## What passes through our server

Our server is a small program that runs on Cloudflare. It has three jobs.

**1. Link previews.** When you keep a link, the app sends the link's address to our server, which fetches the page and sends back its title, description, picture and text. The result may be cached for up to 24 hours so the same page is not fetched again. We do not log the addresses you send and we do not connect them to you.

**2. Stock pictures.** For a post with no picture, the phone chooses a few generic words (for example "garden" or "birthday cake") and asks our server for photos. The server asks Pixabay and passes the photos back. Only generic words are sent. Names are never sent, and posts about health, money or legal matters are never looked up. Results are cached for 24 hours. We do not log the words.

**3. Your Shoebox email address (Shoebox Plus).** If you turn this on, you give a first name and the app asks our server for an address such as `sam-k3t7m2qa@inmyshoebox.com`. When you forward an email to it, our server seals that email to a public key your phone gave us, and keeps only the sealed copy until your phone collects it: the sender's address and name, the subject, the text, links, and up to six attachments (PDFs and pictures). Only your phone holds the key that opens it. We keep it for up to 7 days, and delete it as soon as your phone has saved the post made from it. We cannot read it, do not use it for anything else, and do not share it. The address needs Shoebox Plus. To check the purchase, your phone sends Apple's signed receipt for it to our server, which keeps the purchase's transaction number so one purchase works on at most five phones.

Newsletters and school notices can include children's names and details. Shoebox is not made for children and we do not knowingly collect information from children. A parent or other adult chooses what to forward. Any such email is deleted from our server after 7 days at most. The line you write in Settings about who your mail is about is read on your phone and is never sent to us.

## What we keep, and for how long

| What | Why | How long |
|---|---|---|
| Forwarded email and attachments | So your phone can collect them | Up to 7 days, or until your phone has saved them |
| Your email address and its mailbox record | So mail reaches you | Until 90 days after your phone last asked for mail, or until you choose Delete everything |
| Link and picture results | Speed | Up to 24 hours |
| Rate-limit counters | Stop abuse | An hour or a day. They hold only a scrambled form of a network address, never the address itself |

We do not keep a list of who uses Shoebox, and we cannot see your posts.

## Companies that help us run Shoebox

- **Cloudflare** hosts our server and delivers email to it. It sees ordinary network information (such as your network address) when your phone connects, as any web host does.
- **Pixabay** supplies stock photos. It receives the generic search words from our server, not from you, and does not learn who you are.
- **Apple** provides the App Store, TestFlight, iCloud and in-app purchases. Apple handles your payment. We do not see your card or Apple account details.

We do not sell or rent personal information, and we do not share it for advertising.

## Your choices

- **Delete everything** (Settings) deletes all your posts from the phone and asks our server to delete your address, mailbox record, waiting email and the link to your purchase. If your phone is offline at that moment, the app asks again each time it opens until our server confirms. Backups in Files and iCloud Drive stay until you delete them.
- Deleting the app removes your posts and settings from the phone. It does not remove backup files, or your address on our server. Use Delete everything first.
- You can stop forwarding email at any time. Without new mail, your address expires 90 days after your phone last asked for mail.

## Your rights

**California.** In the last 12 months we have not sold or shared personal information. The only personal information we hold is what is described above, kept only while you use the email feature. You may ask us what we hold about you, ask us to correct or delete it, and we will not treat you differently for asking. Write to support@inmyshoebox.com from the address you want checked, and tell us your Shoebox email address.

**European Economic Area, United Kingdom and similar laws.** Shoebox is not offered in EU storefronts. If the law of your place gives you rights over personal data (access, correction, deletion, restriction, objection, portability), you may use them by writing to support@inmyshoebox.com. We use your data only to deliver the features you ask for (running the service you asked for, and our legitimate interest in keeping it safe from abuse). You may complain to your local data protection authority.

Because we cannot see which phone belongs to which person, we may ask you to prove you hold the mailbox, for example by sending mail from the address you used, before acting on a request. Delete everything in Settings is the quickest way to erase what we hold.

## Children

Shoebox is rated 4+ because it has no objectionable content. It is meant for adults. We do not knowingly collect personal information from children under 13. If you think we have, write to us and we will delete it.

## Security

Mail and addresses are kept in Cloudflare's storage, which encrypts what it holds. Your mailbox is identified by a secret key made on your phone, kept in your Keychain, which we store only in scrambled form. Mail is sealed to a key that stays on your phone, so we cannot read it either. No system is perfectly secure.

## Changes

If we change this policy in a way that matters, the app will say so and the new date will be at the top. The earlier text is available on request.

## Contact

Graham DeNoyer
support@inmyshoebox.com
