# GanyanSosyal – Kredi + AdMob işi (nerede kaldık)

Tarih: 31 Ekim 2026. Proje: Flutter (ganyansosyalprojem), Firebase Auth + Firestore.
Kullanıcı tercihi: kısa, basit, adım adım anlat. Kodu indirilebilir dosya olarak ver, GitHub linki verme, sadece hangi klasöre konacağını yaz, zip verme.

## Amaç
Kullanıcı ödüllü reklam (AdMob) izler, KREDİ kazanır. Kredi sadece kupon paylaşmak için harcanır. Kredi paraya/hediye kartına çevrilmez. Reklam geliri sahibine (Cengiz) gider.

## Kurallar (karar verildi)
- Her video izleme = 100 kredi (`Credits.videoReward` = 100, credits.dart).
- Kupon bedeli = kupon tutarı kadar kredi (örn. 325 ₺ kupon = 325 kredi, `couponCost(c).ceil()`).
- Kredi yetmiyorsa Paylaş butonu turuncu "Video izle +100" olur, seçilen atlar silinmez.
- Yönetici (admin) kredi harcamaz, muaf.
- Yönetici menüsünde "Kredi ver" var, istediği kullanıcıya kredi ekler/düşer.
- Kredi alanı: Firestore `users/{uid}.credits` (int). Alan yoksa varsayılan `Credits.welcome` = 3 (ayar sonraya bırakıldı, yükseltilecek).

## Dosyalar ve yerleri
- lib/credits.dart (yeni): kredi servisi, AdMob ödüllü reklam, ana sayfa KREDİ şeridi, admin kredi penceresi
- lib/predict.dart: Paylaş butonu kredi kilidi, bakiye yazısı, kredi düşme
- lib/feed.dart: ana sayfaya `CreditBar()` eklendi
- lib/admin.dart: "Kredi ver" satırı
- lib/main.dart: `MobileAds.instance.initialize()`
- pubspec.yaml (ana klasör): `google_mobile_ads: ^5.3.0`, sürüm 0.3.1+4
- .github/workflows/build-apk.yml ve build-aab.yml: AndroidManifest'e AdMob APPLICATION_ID ekleyen sed satırı
- firestore.rules: Firebase konsolundan Rules sekmesine yapıştırılır (results bölümündeki bozuk yazımlar düzeltildi)

## Şu anki durum (31 Ekim 2026, akşam)
- AdMob'da uygulama EKLENDİ (GanyanSosyal, Android, Play'de listelenmedi) ve Ödüllü reklam birimi OLUŞTURULDU. Panelde "İnceleme gerekli" uyarısı normal, Play'de yayınlanınca geçer.
- GERÇEK kimlikler koda konuldu:
  - App ID: ca-app-pub-1340335815297540~7852834540 (build-apk.yml ve build-aab.yml, 33. satır sed)
  - Ödüllü birim: ca-app-pub-1340335815297540/1095854500 (lib/credits.dart `kRewardedUnitId`)
- DİKKAT: Bu sürümde GERÇEK reklam gelir. Kendi telefonunda reklama TIKLAMA (hesap kapanır). Test cihazı henüz eklenmedi.
- Derleme hatası 1 (çözüldü): google_mobile_ads 5.3.1 yeni Gradle ile uyumsuz ("Could not get unknown property 'all'"). pubspec.yaml'da `google_mobile_ads: ^9.1.0` yapıldı (Flutter >=3.38.1 / Dart ^3.10 ister).
- Derleme geçti, APK yüklendi AMA açılışta çöküyor: "Unable to get provider androidx.startup.InitializationProvider ... Failed to create an instance of androidx.work.impl.WorkDatabase". Sebep büyük ihtimal R8 küçültmesi (Room/WorkDatabase sınıfı silinmiş).
- Yapılan düzeltme: build-apk.yml ve build-aab.yml içindeki python bloğuna release için `isMinifyEnabled = false` ve `isShrinkResources = false` eklendi. Kullanıcı bu dosyaları GitHub'a yükleyip APK'yı YENİDEN derliyor (ilk deneme erken açılmış olabilir). Hata ekranında r8 isimleri (eh5, xy2, m43) görünüyorsa kurulu APK eski ayarlıdır.
- Hâlâ çökerse sıradaki fikirler: (a) hata ekranının en alt "Caused by" satırını iste (asıl sebep orada, örn. ClassNotFound WorkDatabase_Impl / SQLite / Room); (b) workflow'a proguard kuralı ekle (-keep class androidx.work.** , -keep class * extends androidx.room.RoomDatabase); (c) google_mobile_ads'i test için ^8.x'e düşür veya android/gradle'a androidx.work/room sürümünü sabitle.
- Eski APK yüklüyse önce telefondan sil, yenisini kur.

## Sıradaki adımlar
1. Yeni APK açılıyor mu bak. Açılırsa telefonda test: Özel DNS KAPALI. KREDİ şeridi görünür, kredi yetmeyince turuncu "Video izle +100", reklamı sonuna kadar izle -> +100 kredi, kupon paylaşınca kredi düşer, admin muaf + "Kredi ver" çalışır. Reklam yeni birimde bir saate kadar gelmeyebilir.
2. Kendi cihazını AdMob'da TEST CİHAZI yap (AdMob > Ayarlar > Test cihazları, reklam kimliği ile).
3. AdMob ödeme ayrıntılarını doldur. Play Console > Veri güvenliği: "Reklam kimliği kullanılıyor = Evet".
4. Play yayınlanınca AdMob'da uygulamayı mağaza kaydına bağla (kimlikler değişmez).
5. Play'e yeni sürüm yükle (versiyon numarasını artır, şu an 0.3.1+4). Kapalı test yarın (1 Kasım) bitiyor.

## Notlar
- Ödüllü reklamın kapatma/atlama süresini reklamveren belirler, ayar yok. Kod krediyi sadece ödül olayı gelince (sonuna kadar izlenince) verir, erken kapatana kredi yok.
- Tahmini kazanç: Türkiye'de video başına kabaca 0,5-2 TL.
- Telefondan .yml indirmek bazen olmuyor: GitHub'da dosyayı kalem simgesiyle elle düzenlet.

## Sonraya bırakılanlar
- Hediye kredi (welcome=3) ve kupon bedeli ayarları gözden geçirilecek.
- Güvenlik: kredi şu an istemciden yazılıyor, hile yapılabilir. Yayın öncesi Firebase Functions + AdMob SSV (sunucu doğrulama) ile kredi sunucudan verilmeli ve Firestore kuralında `credits` alanı kullanıcıya kapatılmalı.
- Günlük video izleme sınırı konuşulabilir.
- Profile kredi kutusu eklenebilir.

## Dikkat (politika)
- Uygulama at yarışı tahmini içeriyor. Gerçek bahis oynatma yok. AdMob/Play'e "at yarışı tahmin ve sosyal paylaşım" olarak başvur. Kredi paraya çevrilmez, kullanıcıyı reklama tıklamaya teşvik etme, sadece "izle, kredi kazan".
