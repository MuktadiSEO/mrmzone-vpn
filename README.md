# MRMZone VPN

ফ্রি ভিপিএন — মোবাইল (Android) ও কম্পিউটার (Windows / macOS / Linux) এর জন্য।
বিভিন্ন দেশের সার্ভারে এক ক্লিকে কানেক্ট করা যায়, কোনো অ্যাকাউন্ট বা পেমেন্ট লাগে না।

Free VPN for Android and desktop. Connect to servers in many countries with one tap — no account, no payment.

| | মোবাইল (`mobile/`) | কম্পিউটার (`desktop/`) |
|---|---|---|
| প্রযুক্তি | Flutter + openvpn_flutter (OpenVPN 2.7) | Electron + OpenVPN |
| প্ল্যাটফর্ম | Android 5.0+ (iOS: নিচের নোট দেখুন) | Windows 10/11, macOS, Linux |
| ফাইল | `MRMZone-VPN-android.apk` | `.exe` installer / portable, `.dmg`, `.AppImage`, `.deb` |

## ফ্রি সার্ভার কোথা থেকে আসে?

সার্ভারগুলো আসে **[VPN Gate](https://www.vpngate.net/en/)** থেকে — জাপানের University of Tsukuba-র
একটি একাডেমিক প্রজেক্ট, যেখানে স্বেচ্ছাসেবকরা ফ্রিতে OpenVPN সার্ভার চালান (জাপান, কোরিয়া, যুক্তরাষ্ট্র,
থাইল্যান্ড, রাশিয়া ইত্যাদি)। অ্যাপ প্রতিবার লাইভ সার্ভার লিস্ট ডাউনলোড করে, দেশ অনুযায়ী সাজায়, আর
সেরা সার্ভারে কানেক্ট করে। কোনো সার্ভার সাড়া না দিলে **অটোমেটিক পরের সার্ভার** (প্রতি দেশে ৩টি পর্যন্ত) চেষ্টা করে।

> ⚠️ ফ্রি সার্ভার স্বেচ্ছাসেবকদের, তাই স্পিড ও কোন দেশ পাওয়া যাবে তা সময়ভেদে বদলায়। ব্যাংকিং বা খুব
> গোপন কাজে ফ্রি পাবলিক ভিপিএন ব্যবহার না করাই ভালো।

## ফিচার

- 🌍 দেশ অনুযায়ী সার্ভার লিস্ট — পতাকা, স্পিড রেটিং (★), পিং, সার্ভার সংখ্যা
- ⚡ Quick connect — শেষ ব্যবহৃত দেশ, না থাকলে সবচেয়ে ভালো সার্ভার
- 🔁 সার্ভার ফেইল করলে অটো-ফেইলওভার
- 🔍 সার্চ, সর্ট (A–Z / Fastest / Lowest ping / Most servers), ⭐ Favorites
- 📊 কানেকশন টাইম, ডাউনলোড/আপলোড, আপনার বর্তমান পাবলিক IP
- 🛒 অ্যামাজন-স্টাইল থিম (নেভি হেডার, হলুদ/কমলা বাটন, প্রোডাক্ট-কার্ড লেআউট)
- 💾 সার্ভার লিস্ট ক্যাশ — ইন্টারনেট সমস্যা হলেও সেভ করা লিস্ট দেখায়

## ডাউনলোড / বিল্ড

প্রতিবার GitHub-এ push করলে **GitHub Actions** নিজে থেকেই সব অ্যাপ বিল্ড করে
(`.github/workflows/build.yml`):

1. GitHub রিপোজিটরিতে **Actions** ট্যাবে যান → সর্বশেষ "Build apps" রান খুলুন
2. নিচে **Artifacts** থেকে ডাউনলোড করুন: `MRMZone-VPN-android`, `MRMZone-VPN-Windows`, `MRMZone-VPN-macOS`, `MRMZone-VPN-Linux`
3. `v1.0.0` এর মতো একটি ট্যাগ push করলে সব ফাইলসহ একটি **Release** তৈরি হয়

### মোবাইল (Android) ইনস্টল

1. `MRMZone-VPN-android.apk` ফোনে নিন → খুলুন → "Install unknown apps" অনুমতি দিন
2. অ্যাপ খুলে দেশ বেছে **Connect** চাপুন → প্রথমবার Android "Connection request" দেখাবে → **OK**

### কম্পিউটার ইনস্টল

অ্যাপটি ফ্রি, ওপেন-সোর্স **OpenVPN** ইঞ্জিন ব্যবহার করে — একবার ইনস্টল করতে হয়:

- **Windows:** [openvpn.net/community-downloads](https://openvpn.net/community-downloads/) থেকে Windows installer
  ইনস্টল করুন (ডিফল্ট অপশন)। তারপর `MRMZone-VPN-...-win-x64.exe` ইনস্টল করুন। অ্যাপ Administrator হিসেবে চলবে
  (ভিপিএন চালাতে Windows এটা চায়)।
- **macOS:** Terminal-এ `brew install openvpn`, তারপর `.dmg` থেকে অ্যাপ ইনস্টল। কানেক্টের সময় Mac পাসওয়ার্ড চাইবে।
  (অ্যাপটি sign করা নেই, তাই প্রথমবার right-click → Open করুন।)
- **Linux:** `sudo apt install openvpn` (`.deb` ইনস্টল করলে নিজেই আসে)। কানেক্টের সময় পাসওয়ার্ড চাইবে।

OpenVPN ইনস্টল না থাকলে অ্যাপ নিজেই হলুদ বক্সে কী করতে হবে দেখাবে।

## ডেভেলপারদের জন্য

```bash
# Desktop
cd desktop
npm install
npm test          # 15 tests (parser, OpenVPN controller, connect/failover flow)
npm start         # run the app
npm run dist      # build installers for this OS

# Mobile
cd mobile
flutter pub get
flutter test      # parser, controller (fake engine) and UI tests
flutter run       # on a connected Android phone
flutter build apk --release
```

### প্রজেক্ট স্ট্রাকচার

```
desktop/src/vpngate.js     সার্ভার লিস্ট পার্সার (CSV → দেশ)
desktop/src/openvpn.js     OpenVPN প্রসেস + management interface কন্ট্রোল
desktop/src/main.js        Electron main: কানেক্ট, ফেইলওভার, ক্যাশ, IP চেক
desktop/src/renderer/      UI (HTML/CSS/JS)
mobile/lib/services/       পার্সার + VpnController (কানেক্ট, ফেইলওভার, ক্যাশ)
mobile/lib/screens/        Home, Countries, Favorites, Servers স্ক্রিন
```

### নোট

- **iOS:** Apple-এ ভিপিএন চালাতে Network Extension, Apple Developer অ্যাকাউন্ট ($99/বছর) আর Mac-এ Xcode লাগে।
  কোড iOS-এর জন্য প্রস্তুত (`group.com.mrmzone.vpn`, `com.mrmzone.vpn.VPNExtension`), তবে extension টার্গেট
  [openvpn_flutter iOS setup](https://pub.dev/packages/openvpn_flutter#ios-setup) অনুযায়ী Xcode-এ যোগ করতে হবে।
- **Google Play-তে দিতে:** নিজের keystore দিয়ে sign করুন (এখন debug key দিয়ে sign করা, সরাসরি ইনস্টলের জন্য),
  এবং Play Console-এ VPN declaration পূরণ করুন।
- লাইসেন্স: openvpn_flutter GPLv3, OpenVPN GPLv2।
