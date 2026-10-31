# GanyanSosyal – Kredi + AdMob + LevelPlay işi (nerede kaldık)

Tarih: 31 Ekim 2026 (21:45'te güncellendi). Proje: Flutter (ganyansosyalprojem), Firebase Auth + Firestore.
Kullanıcı tercihi: kısa, basit, adım adım anlat. Kodu indirilebilir DOSYA olarak ver (tek tek), GitHub linki verme, sadece hangi klasöre konacağını yaz, zip verme (kullanıcı zip verirse bile çıktıyı tek tek dosya ver). Telefondan çalışıyor, ekran görüntüsü atar.

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

## Sürüm numarası (21:50)
- Şimdi test aşaması: sürüm 0.3.1+5 kalıyor, DEĞİŞTİRME. Test APK'sı için numara artırmaya gerek yok.
- Test bitip Play'e yüklenecekse `pubspec.yaml` içindeki `version:` satırı artırılır (örn. 0.3.1+6). Play'e her yüklemede `+` sonrası sayı büyümeli.
- Sonraya kalan: LevelPlay çalışıyorsa sürümü artır, AAB derle, Play'e yükle.

## Sıradaki adımlar
1. Yeni zip/dosyaları GitHub'a yükle, APK derle. Derleme hatası varsa hata metnini (en alttaki kırmızı satırlar) at, düzeltilsin.
2. APK açılıyorsa test: Özel DNS KAPALI. Video izle butonu -> LevelPlay reklamı gelmeli. Gelmezse (Android logcat/hata) AdMob yedeği devreye girer. Reklam sonuna kadar izlenince +100 kredi.
3. LevelPlay panelinde Test devices'a telefonu ekle, test reklamıyla dene (kendi reklamına tıklama).
4. Reklam hâlâ azsa LevelPlay'e AppLovin veya Pangle ekle (Networks > Setup).
5. LevelPlay/Unity/AdMob ödeme bilgilerini doldur. Unity Türkiye'ye ödeme koşullarını (alt limit, vergi formu) kayıttan önce teyit et. Play Console > Veri güvenliği: \"Reklam kimliği kullanılıyor = Evet\".
6. Play yayınlanınca LevelPlay'de ve AdMob'da uygulamayı mağaza kaydına bağla (Not live yet -> Live app). Play'e yeni sürüm yükle (versiyonu artır, şu an 0.3.1+4). Kapalı test 1 Kasım'da bitiyor.

## Zip temizlik uyarısı (31 Ekim akşam)
- `lib/credits (1).dart` ESKİ kopya (CreditBar, LevelPlay yok). Sil. Doğrusu `lib/credits.dart`.
- `lib/pubspec.yaml` ESKİ kopya (+4, google_mobile_ads ^5.3.0). Sil. Doğrusu ana klasördeki `pubspec.yaml` (+5, ^9.1.0, LevelPlay paketleri).
- `lib/frames.dart` ile `assets/frames.dart` çift olabilir, kontrol et.

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
