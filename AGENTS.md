# GanyanSosyal – Kredi + AdMob + LevelPlay işi (nerede kaldık)

Tarih: 1 Kasım 2026 (02:30'da güncellendi). Proje: Flutter (ganyansosyalprojem), Firebase Auth + Firestore.
Kullanıcı tercihi: kısa, basit, adım adım anlat, kafası karışınca tek tek yönlendir (telefondan Play Console/Firebase kullanıyor, ekran görüntüsü atıyor). Kodu indirilebilir DOSYA olarak ver (tek tek), GitHub linki verme, sadece hangi klasöre konacağını yaz, zip verme (kullanıcı zip verirse bile çıktıyı tek tek dosya ver). Telefondan çalışıyor, ekran görüntüsü atar.

## GÜNCEL DURUM (1 Kasım 2026, gece) – Play'e yükleme aşaması
Reklamlar çalışıyor (kullanıcı teyit etti). Şimdi Flutter uygulamasını Play'deki MEVCUT uygulamanın üstüne yüklemeye çalışıyoruz.

**Play'deki uygulama:** "Ganyan Sosyal", paket adı `io.github.ganyansosyal.app`, sürüm adı 1.0.23 (eski repoda başka teknolojiyle yapılmış, sürüm KODU bilinmiyor). Telefonda Play'den yüklü.

**Yapılan değişiklikler (kullanıcı GitHub'a yükledi / yüklüyor):**
- `pubspec.yaml`: `version: 0.3.1+100` (eski kod bilinmediği için büyük sayı), `in_app_update: ^4.2.3` eklendi
- `.github/workflows/build-aab.yml` ve `build-apk.yml`: `flutter create`'ten sonra `sed` ile `applicationId = "io.github.ganyansosyal.app"` yapılıyor (namespace `com.ganyansosyal.ganyansosyal_native` kalıyor, sorun değil)
- `lib/credits.dart`: kullanıcıya görünen "[test] LevelPlay..." hata yazısı kaldırıldı, yerine "Şu an uygun reklam yok. Biraz sonra tekrar dene."
- `lib/update_check.dart` (YENİ): Play In-App Update, uygulama açılınca yeni sürüm varsa tam ekran zorunlu güncelleme (`performImmediateUpdate`). Sadece Play'den yüklenende çalışır. `lib/shell.dart` initState'te `UpdateCheck.run()` çağırıyor.
- (Firebase `minBuild` ile zorunlu güncelleme ekranı denendi, kullanıcı karmaşık bulunca ÇIKARILDI. `splash.dart` orijinal hâline döndü, `package_info_plus` yok.)
- `lib/pubspec.yaml` (eski kopya) kullanıcı tarafından silindi.
- `.github/workflows/export-cert.yml` (YENİ): `KS_BASE64/KS_PASS/KS_ALIAS` secret'larından `upload_cert.pem` ve SHA parmak izlerini üretir.

**Anahtar sorunu (en önemli):**
- Play'deki YÜKLEME anahtarı SHA-256: `2D:4B:F5:AE:C7:01:30:00:88:01:1C:1D:07:21:E8:D3:58:E9:22:20:67:D8:BE:25:C9:9F:F7:0C:A9:7A:BC:4F` (eski repoda üretilmişti, o keystore artık yok)
- Bizim repodaki keystore (`KS_BASE64`) SHA-256: `B5:0A:65:21:63:E0:94:B3:A2:67:B4:F3:17:27:E7:C9:0F:EC:59:7F:28:3C:0A:6E:6E:9E:5D:D2:44:30:8E:A9`, SHA-1: `2B:D9:95:46:F4:36:FD:65:5C:4C:C0:E0:5E:9B:94:69:25:1B:64:F0` (Firebase'de `ganyansosyal native` uygulamasında kayıtlı olan bu)
- İkisi FARKLI, o yüzden Play AAB'yi reddeder. Çözüm: Play Console > Uygulama imzalama > Anahtarı yükleyin > "Sıfırlama talep edin", sebep "Yükleme anahtarımı kaybettim", `upload_cert.pem` (bizim keystore sertifikası) yüklendi. **TALEP GÖNDERİLDİ (1 Kasım 02:31), Google onayı bekleniyor, genelde 1-2 gün, e-posta gelir.** Onaylanmadan AAB yükleme, reddedilir. İsteği iptal etme.

**Firebase durumu:** Projede 2 Android uygulaması var: `io.github.ganyansosyal.app` (SHA-256 `1e:49:02:da...cd:b4` kayıtlı, SHA-1 yok) ve `com.ganyansosyal.ganyansosyal_native` (SHA-1 + SHA-256 bizim keystore). Uygulama Web config kullanıyor (`firebase_options.dart` appId `web:...`), Google ile giriş `serverClientId` ile.

## SIRADAKİ ADIMLAR (sırayla)
1. **Firebase'de `io.github.ganyansosyal.app` Android uygulamasına parmak izi ekle** (Google ile giriş yeni paket adında çalışsın): Project settings > Your apps > Ganyansosyal android > Add fingerprint: bizim SHA-1 + SHA-256 (yukarıda). Ek olarak Play Console > Uygulama imzalama > "Uygulama imzalama anahtarı" bölümündeki SHA-1'i de ekle (Play'den indirenlerde giriş için şart). Gerekirse Google Cloud Console > Credentials'ta Android OAuth istemcisi (paket `io.github.ganyansosyal.app` + SHA-1) kontrol et.
2. GitHub'da `pubspec.yaml`, `build-aab.yml`, `build-apk.yml`, `credits.dart`, `shell.dart`, `update_check.dart` yüklü mü kontrol et, sonra **build-aab** çalıştır, `.aab` indir, sakla (kullanıcı AAB'yi aldı/alıyor).
3. Google sıfırlamayı onaylayınca (e-posta): Play Console > Test ve yayınla > Kapalı test (veya Üretim) > yeni sürüm > `.aab` yükle. Hata verirse mesajı al (imza/sürüm kodu). Sürüm kodu 100 yetmezse `+` sonrasını büyüt.
4. Play Console > Veri güvenliği: "Reklam kimliği kullanılıyor = Evet". Üretim erişimi başvurusu formu bu aşamada (kapalı test şartı için 1 Kasım'da bitiyor yazıyordu, Play'deki durumu kontrol et).
5. Yayın sonrası: AdMob'da uygulamayı Play listesine bağla (paket `io.github.ganyansosyal.app`), LevelPlay'de paket adı alanını güncelle ve "Live app" yap. AdMob App ID (`~7852834540`) paket adına bağlı değil, değişmez.
6. `in_app_update` ilk `+100` ile gidiyor. Güncelleme penceresi sonraki sürümde (`+101` ve üstü) çıkar.

## Amaç
Kullanıcı ödüllü reklam (LevelPlay mediation: ironSource + Unity Ads + AdMob) izler, KREDİ kazanır. Kredi sadece kupon paylaşmak için harcanır. Kredi paraya/hediye kartına çevrilmez. Reklam geliri sahibine (Cengiz) gider.

## Kurallar (karar verildi)
- Her video izleme = 100 kredi (`Credits.videoReward` = 100, credits.dart).
- Kupon bedeli = kupon tutarı kadar kredi (örn. 325 ₺ kupon = 325 kredi, `couponCost(c).ceil()`).
- Kredi yetmiyorsa Paylaş butonu turuncu "Video izle +100" olur, seçilen atlar silinmez.
- Yönetici (admin) kredi harcamaz, muaf.
- Yönetici menüsünde "Kredi ver" var, istediği kullanıcıya kredi ekler/düşer.
- Kredi alanı: Firestore `users/{uid}.credits` (int). Alan yoksa varsayılan `Credits.welcome` = 3 (ayar sonraya bırakıldı, yükseltilecek).

## Dosyalar ve yerleri
- lib/credits.dart: kredi servisi, `_playVideo()` önce LevelPlay, reklam yoksa `_playAdMobDirect()` (eski doğrudan AdMob), ana sayfada küçük kredi hapı `CreditChip` (Öne Çıkan Tahminciler başlığının sağında; eski büyük `CreditBar` şeridi kaldırıldı), admin kredi penceresi
- lib/predict.dart: Paylaş butonu kredi kilidi, bakiye yazısı, kredi düşme
- lib/feed.dart: ana sayfaya `CreditChip()` eklendi (satır ~525)
- lib/admin.dart: "Kredi ver" satırı
- lib/main.dart: `MobileAds.instance.initialize()` + `LevelPlayAds.instance.init()` (arka planda)
- lib/levelplay_ads.dart (YENİ): LevelPlay sarmalayıcı. `playRewarded()` -> true=izlendi, false=erken kapandı, null=reklam yok (yedeğe geç)
- pubspec.yaml (ana klasör): `google_mobile_ads: ^9.1.0`, YENİ: `unity_levelplay_mediation: ^9.4.0` (docs.unity.com'dan doğrulandı). `levelplay_admob_adapter` ve `levelplay_unityads_adapter` pub.dev'de YOK (404), silindi. Adaptörler Flutter paketi değil, Android Gradle bağımlılığı olabilir; satırları Unity docs > LevelPlay SDK for Android > Networks sayfalarından alınacak. Plugin 9.3+ Kotlin 2.0+ ister. Android'e play-services-ads-identifier:18.2.0, play-services-appset:16.1.0 ve AD_ID izni gerekebilir. Sürüm 0.3.1+5
- .github/workflows/build-apk.yml ve build-aab.yml: AndroidManifest'e AdMob APPLICATION_ID ekleyen sed satırı + YENİ: ACCESS_NETWORK_STATE izni sed satırı (LevelPlay için)
- firestore.rules: Firebase konsolundan Rules sekmesine yapıştırılır (results bölümündeki bozuk yazımlar düzeltildi)

## Şu anki durum (31 Ekim 2026, gece)
- SORUN: Doğrudan AdMob ödüllü reklam 3 izlemeden sonra gelmedi (\"Reklam yüklenemedi ya da sonuna kadar izlenmedi\"). İki cihazda da aynı. Kod doğru, sebep büyük ihtimal AdMob'un Türkiye'de/yeni birimde reklam (fill) vermemesi. Kod hata kodunu yutuyor (`onAdFailedToLoad`'da `e` loglanmıyor).
- ÇÖZÜM YOLU: Mediation. Unity LevelPlay (platform.ironsrc.com) kullanılıyor. Panelde YAPILDI:
  - Unity hesabı (Google ile), organization: weptasarimlari, Org Core ID: 18968444928009
  - Unity Monetization'da proje GanyanSosyal, Android uygulama, Game ID: 800419201, Rewarded placement ID: BP_Rewarded_Android
  - Unity Stats API Key oluşturuldu (LevelPlay Networks > UnityAds'e girildi; anahtarı paylaşma, gerekirse Unity > Monetization > Settings > API management'tan yenile)
  - LevelPlay'de uygulama: Ganyansosyal (Android, \"Not live yet\", COPPA: Not directed), paket: com.ganyansosyal.ganyansosyal_native
  - LevelPlay App Key: 2929a4b7d
  - LevelPlay Ad unit: \"Rewarded Kredi\", kimlik: avoubet78r5s78d4 (ekran görüntüsünden okundu, panelden Setup > Ad units'ten TEKRAR KONTROL ET)
  - Networks: ironSource, Unity Ads, Google AdMob aktif. Instances'ta üçünde Rewarded ✓ (Google: App ID ~7852834540, ad unit /1095854500)
  - Bidder auto-setup KAPALI bırakıldı (Key ID/Secret key gerektiriyor).
- KOD YAZILDI ama DERLENMEDİ/TEST EDİLMEDİ (ortamda internet ve Flutter yoktu): levelplay_ads.dart, credits.dart, main.dart, pubspec.yaml, build-apk.yml, build-aab.yml. Kullanıcı GitHub'da build alıp test edecek.
- RİSKLER: (a) `unity_levelplay_mediation`, `levelplay_admob_adapter`, `levelplay_unityads_adapter` paket adları/sürümleri ve LevelPlay Dart API'si (LevelPlayInitRequest.builder, LevelPlayRewardedAd, listener imzaları) hafızadan yazıldı, derleme hatası çıkabilir; (b) Android tarafında adaptör gradle ayarı gerekebilir; (c) google_mobile_ads ile LevelPlay admob adaptörü sürüm çakışması çıkabilir.
- Eski kayıtlar: google_mobile_ads 5.3.1 Gradle hatası ^9.1.0 ile çözüldü; açılış çökmesi (androidx.work WorkDatabase) için release'te `isMinifyEnabled = false` eklendi. Hâlâ çökerse: \"Caused by\" satırını iste, proguard `-keep class androidx.work.**`, `-keep class * extends androidx.room.RoomDatabase`.
- DİKKAT: GERÇEK reklam gelir. Kendi telefonunda reklama TIKLAMA (hesap kapanır). Test cihazı eklenmedi (LevelPlay > Setup > Test devices ve AdMob > Test cihazları).
- Eski APK yüklüyse önce telefondan sil, yenisini kur.

## Test sonucu (22:12) ve yapılanlar
- APK derlendi, uygulama açılıyor, "Video izle" çalışıyor. Hata mesajı artık ekranda ([test] satırı, reklam çalışınca kaldırılacak).
- LevelPlay: kod 509 "No fill" (SDK çalışıyor, ad unit kimliği doğru, reklam yok). AdMob direkt: kod 3 "Account not approved yet" => AdMob hesabı ONAYSIZ (adres/ödeme/telefon doğrulaması, uygulamayı Play'e bağla). Eski "reklam gelmiyor" sebebi buydu.
- 22:20: Unity Ads adaptörü workflow'lara eklendi: `implementation("com.unity3d.ads-mediation:unityads-adapter:5.15.0")` (build.gradle.kts'ye append) + AD_ID izni. Dokümandan doğrulandı. Uyumluluk (adaptör 5.x <-> plugin 9.4.0) test edilecek.
- AdMob adaptörü (admob-adapter:5.19.0) bilerek EKLENMEDİ: kendi içinde yeni Google Mobile Ads SDK taşır, google_mobile_ads ile çakışabilir. AdMob onaylanınca düşünülecek.

## Site / panel linkleri (kolay bulmak için)
- LevelPlay paneli: https://platform.ironsrc.com (üstte uygulama: Ganyansosyal). Menü yolları:
  - Setup > Ad units (reklam birimi kimliği), Instances (hangi ağ açık), Networks, Test devices
  - Reports > Performance (kazanç, gösterim)
  - Ad Quality > Manage > Rules (reklam engelleme kuralı), Ad Quality > Review > Creatives (gelen reklamları gör/engelle)
- Unity (Monetization, placement, Stats API key): https://cloud.unity.com (organization: weptasarimlari)
- AdMob (hesap onayı, adres/ödeme/PIN, uygulamayı Play'e bağla): https://admob.google.com
- Unity docs LevelPlay Flutter: https://docs.unity.com/en-us/grow/levelplay/sdk/flutter/plugin-integration
- Unity docs LevelPlay Android adaptörler: https://docs.unity.com/en-us/grow/levelplay/sdk/android/mediation-networks (Unity Ads: .../android/networks/guides/unity-ads, AdMob: .../android/networks/guides/google-admob)
- Flutter paketi: https://pub.dev/packages/unity_levelplay_mediation (sürüm 9.4.0)
- GitHub repo Actions (APK derle / AAB): github.com/ganyansosyal/ganyansosyalprojem > Actions
- Play Console: https://play.google.com/console (kapalı test, Veri güvenliği)

## Test sonucu 22:45: Unity Ads reklamı GELDİ, LevelPlay çalışıyor
- Gelen reklamlar oynanabilir oyun reklamları (Whiteout Survival, Kingshot): uzun, kapatma belirsiz, "Mağazayı aç" yazısı kapat sanılıp tıklanabilir (tıklama riski). Çözüm: Ad Quality > Rules/Creatives'ten engelle (kademeli; Games kategorisini tamamen kapatma, fill düşer). AdMob onayı + AppLovin/Pangle eklenince çeşitlilik artar.
- Yapılacak: butonun altına "Reklam 30 sn sürebilir, sonunda kapat çıkar" bilgi satırı.

## Durum 23:10 (gece güncellemesi)
- Unity Ads instance DEVRE DIŞI bırakıldı (LevelPlay > Setup > Instances > UnityAds > satırda ⋯ > Deactivate > Save; Game ID alanına 800419201 yazmak gerekti). Sebep: Unity'nin oynanabilir (playable) reklamları uzun, ekrana dokunmadan kapat çıkmıyor, "Download Now/Mağazayı aç" yanlış tıklama riski.
- Sonuç: şu an hiçbir reklam gelmiyor. LevelPlay 509 "No fill" (ironSource boş), AdMob 3 "Account not approved yet". Kullanıcılar kredi kazanamıyor. Geçici çözüm: Unity'yi geri aç (⋯ > Activate > Save) YA DA yönetici menüsü "Kredi ver" ile elle kredi.
- Yapılacak (öncelik sırası): 1) AdMob hesap onayı (adres, ödeme, telefon/PIN doğrulaması, admob.google.com). 2) AppLovin ve Pangle hesabı aç, LevelPlay > Setup > Networks > Setup, koda Android Gradle adaptörü ekle (Unity Ads gibi). 3) Onay gelince Unity'yi kapalı tut. 4) Butonun altına "Reklam 30 sn sürebilir, sonunda kapat çıkar" bilgisi (henüz eklenmedi). 5) Test devices ekle (kendi telefonunda gerçek reklama tıklama/tekrar izleme yapma, hesap riski).
- Ad Quality > Rules sayfası engelleme DEĞİL, bildirim kuralı (trigger: Category/Title/Developer/Package vb.). Creatives sayfası: 5+ gösterim olunca listeler, oradan tek tek engellenebilir.
- Uygulamada geçici hata yazısı var: reklam gelmezse snackbar'da "[test] LevelPlay: ..." ve AdMob hatası görünür. Yayın öncesi kaldırılacak (credits.dart, levelplay_ads.dart lastError).
- "Kendi telefonunda reklam izleme": gösterim sayılır ama tekrar tekrar izlemek geçersiz trafik riski; para da çok az. Test devices kullan.
- Gelir: ödeme için LevelPlay ana sayfasında "payment preferences" ve "company info" doldurulmalı (şirket yok; Individual seçeneği var mı bak, vergi için mali müşavire danış).

## AppLovin (23:15)
- AppLovin hesabı kullanıcıda zaten açık. Workflow'lara `applovin-adapter:5.10.0` eklendi (SDK'yı içinde taşır, Unity docs'tan doğrulandı).
- LevelPlay panelinde yapılacak: Setup > Networks > AppLovin > Setup. AppLovin Account > Keys sayfasından: Report Key (network kurulum sayfasına), SDK Key (uygulamanın instance sayfasına). Sonra Instances'ta AppLovin Rewarded instance ekle.
- AppLovin Admin > Manage Apps > Rewarded: Frequency capping yok, Display Pre-Video Modal = NO, Post-Video Modal = NO, Callback = Client-side only.
- Pangle adaptörü 5.27.0, Mintegral 5.23.0 (Gradle artifact adı için docs.unity.com/en-us/grow/levelplay/sdk/android/networks/guides/pangle ve /mintegral).

## Sürüm numarası (21:50)
- Play'e her yüklemede `pubspec.yaml` `version:` içindeki `+` sonrası sayı büyümeli (şu an +100).

## ESKİ adımlar (çoğu bitti, referans)
1. Yeni zip/dosyaları GitHub'a yükle, APK derle. Derleme hatası varsa hata metnini (en alttaki kırmızı satırlar) at, düzeltilsin.
2. APK açılıyorsa test: Özel DNS KAPALI. Video izle butonu -> LevelPlay reklamı gelmeli. Gelmezse (Android logcat/hata) AdMob yedeği devreye girer. Reklam sonuna kadar izlenince +100 kredi.
3. LevelPlay panelinde Test devices'a telefonu ekle, test reklamıyla dene (kendi reklamına tıklama).
4. Reklam hâlâ azsa LevelPlay'e AppLovin veya Pangle ekle (Networks > Setup).
5. LevelPlay/Unity/AdMob ödeme bilgilerini doldur. Unity Türkiye'ye ödeme koşullarını (alt limit, vergi formu) kayıttan önce teyit et. Play Console > Veri güvenliği: \"Reklam kimliği kullanılıyor = Evet\".
6. Play yayınlanınca LevelPlay'de ve AdMob'da uygulamayı mağaza kaydına bağla (Not live yet -> Live app). Play'e yeni sürüm yükle (versiyonu artır, şu an 0.3.1+4). Kapalı test 1 Kasım'da bitiyor.

## Notlar
- Ödüllü reklamın kapatma/atlama süresini reklamveren belirler, ayar yok. Kod krediyi sadece ödül olayı gelince (sonuna kadar izlenince) verir, erken kapatana kredi yok.
- Tahmini kazanç: Türkiye'de video başına kabaca 0,5-2 TL.
- Hata ayıklama için `onAdFailedToLoad` ve LevelPlay hata mesajları artık debugPrint ile loglanıyor (LevelPlay tarafı).
- Telefondan .yml indirmek bazen olmuyor: GitHub'da dosyayı kalem simgesiyle elle düzenlet.

## Sonraya bırakılanlar
- Hediye kredi (welcome=3) ve kupon bedeli ayarları gözden geçirilecek.
- Güvenlik: kredi şu an istemciden yazılıyor, hile yapılabilir. Yayın öncesi Firebase Functions + AdMob SSV (sunucu doğrulama) ile kredi sunucudan verilmeli ve Firestore kuralında `credits` alanı kullanıcıya kapatılmalı.
- Günlük video izleme sınırı konuşulabilir.
- Profile kredi kutusu eklenebilir.

## Dikkat (politika)
- Uygulama at yarışı tahmini içeriyor. Gerçek bahis oynatma yok. AdMob/Play'e "at yarışı tahmin ve sosyal paylaşım" olarak başvur. Kredi paraya çevrilmez, kullanıcıyı reklama tıklamaya teşvik etme, sadece "izle, kredi kazan".
