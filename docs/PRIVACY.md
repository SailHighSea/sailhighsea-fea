# Privacy policy

This is the same text as the in-app page (Appearance, Privacy policy). It lives in `lib/features/privacy/privacy_policy.dart`; a test keeps this file in step.

> Before publishing to a store: add the publisher name, a contact email and the date, and host this text at a public URL (App Store Connect and Play Console both ask for one).

## What this app is

Family Expenses is a household expense tracker. Nothing is shared with the app developer: everything stays on your device or in your own Google account. It does not show ads, does not include analytics or tracking libraries, and does not sell or share your data.

## What is stored, and where

Your expenses, categories, budgets, goals and bills are stored in a database on this device first. The app works offline. Settings such as your theme and currency stay on this device.

## If you sign in with a household

When the app is set up with a Supabase project, your email address, name, role and household data are stored on that server so family members can share them. Who can see what is enforced on the server by your role: owners and admins see everything, other members see what the owner allows. Invite codes are stored hashed, can be used once and expire after 24 hours.

## Google Sheets

If you connect Google Sheets, the app asks for access to only the spreadsheet it creates, and writes your expenses to it. The access token is kept on the server in an encrypted store (or on the device in Google Sheets mode) and you can disconnect at any time. Anything in that sheet is then also subject to your Google account.

## Receipt photos

A receipt photo is read on your device. It stays on the device unless you switch on "Share the photo with the household", in which case it is uploaded to a private storage area that only people who can see that expense can open.

## App lock and your device

The app lock asks your device to confirm your fingerprint, face or PIN. The app never sees or stores biometric data.

## Exporting and deleting

You can back up everything to a file, or export your expenses as a CSV file, at any time from Appearance. Deleting an expense removes it from your devices and the household. To remove an account and its server data, ask the household owner or the person who runs the server.

## Children

The app is meant for families and is managed by an adult household owner.

