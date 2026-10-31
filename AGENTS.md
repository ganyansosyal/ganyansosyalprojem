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

## Şu anki durum
- Kod yazıldı, DERLENMEDİ (ortamda Flutter yok). 8 dosya kullanıcıya verildi, yüklemesi ve GitHub Actions'ta derlemesi bekleniyor. Hata çıkarsa hata mesajı istenecek.
- Reklam kimlikleri şu an Google TEST kimlikleri (gerçek para kazandırmaz):
  - App ID: ca-app-pub-3940256099942544~3347511713 (iki workflow dosyasında)
  - Ödüllü birim: ca-app-pub-3940256099942544/5224354917 (credits.dart içinde `kRewardedUnitId`)
- AdMob hesabı AÇILDI (Türkiye, TL). Panelde 4 görev var, "Ödeme ayrıntılarını ekle" yapılmadı.
- Uygulama AdMob'a HENÜZ EKLENMEDİ, gerçek kimlikler yok.
- Google Play kapalı test yarın bitiyor, kullanıcı yeni sürümü yükleyecek.

## Sıradaki adımlar
1. Kullanıcı 8 dosyayı yükler, GitHub Actions "APK derle" çalıştırır. Derleme hatası varsa düzelt.
2. Telefonda test: Özel DNS KAPALI olmalı (dns.adguard.com reklamı ve admob.google.com'u engelliyordu). "Video izle" test reklamı açmalı, kredi +100 gelmeli.
3. AdMob'da: Uygulamalar > Uygulama ekle > Android > Play'de yayınlanmadı > ad GanyanSosyal. Kullanıcıdan App ID (~ işaretli) ve Ödüllü reklam birimi ID'si (/ işaretli) iste.
4. İki kimliği koda koy: 2 workflow dosyasındaki APPLICATION_ID ve credits.dart'taki kRewardedUnitId. Dosyaları yeniden ver.
5. Kendi cihazını AdMob'da TEST CİHAZI olarak ekle (kendi gerçek reklamına tıklama/izleme hesabı kapattırır).
6. AdMob'da ödeme ayrıntılarını doldur. Play Console > Veri güvenliği: "Reklam kimliği kullanılıyor = Evet".
7. Play'e gerçek kimlikli sürüm yükle (versiyon numarasını artır).

## Sonraya bırakılanlar
- Hediye kredi (welcome=3) ve kupon bedeli ayarları gözden geçirilecek.
- Güvenlik: kredi şu an istemciden yazılıyor, hile yapılabilir. Yayın öncesi Firebase Functions + AdMob SSV (sunucu doğrulama) ile kredi sunucudan verilmeli ve Firestore kuralında `credits` alanı kullanıcıya kapatılmalı.
- Günlük video izleme sınırı konuşulabilir.
- Profile kredi kutusu eklenebilir.

## Dikkat (politika)
- Uygulama at yarışı tahmini içeriyor. Gerçek bahis oynatma yok. AdMob/Play'e "at yarışı tahmin ve sosyal paylaşım" olarak başvur. Kredi paraya çevrilmez, kullanıcıyı reklama tıklamaya teşvik etme, sadece "izle, kredi kazan".
