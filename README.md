# CVSAFE – Şantiye İş Güvenliği ve Otonom İhlal Tespit Asistanı

Proje iki parçadan oluşur:

| Klasör | Ne yapar | Teknoloji |
| --- | --- | --- |
| `backend/` | Yapay zekâ sunucusu: fotoğraf/video/kamera analizi, uyarılar, istatistik, PDF rapor | Python, FastAPI, YOLO11 (Ultralytics), OpenCV, SQLite |
| `mobile/` | Saha uygulaması (`lib/main.dart`) **ve** web paneli (`lib/main_panel.dart`) | Flutter (Android, iOS, Web) |

- **Mobil uygulama** sahadaki şantiye şefi içindir: uyarıyı alır, kanıtı görür, müdahaleyi kaydeder ve fotoğraf/video analiz ettirir.
- **Web paneli** ofisteki yönetici ve İSG uzmanı içindir: kamera ekler, tehlikeli bölgeleri fareyle çizer, taşeron ve kullanıcıları yönetir, olay kayıtlarını ve raporları inceler.

İkisi aynı Flutter projesindedir ve aynı kodu (modeller, API, tema) paylaşır.

---

## 1. Yapay zekâ sunucusunu çalıştırma

Gereken: Python 3.10 veya üstü.

```bash
cd backend
python -m venv .venv
# Windows: .venv\Scripts\activate     macOS/Linux: source .venv/bin/activate
pip install -r requirements.txt
```

Sunucuyu başlatın (`CVSAFE_DEMO=1` boş bir panel yerine örnek bir haftalık geçmiş oluşturur):

```bash
# macOS / Linux
CVSAFE_DEMO=1 uvicorn app.main:app --host 0.0.0.0 --port 8000
# Windows PowerShell
$env:CVSAFE_DEMO="1"; uvicorn app.main:app --host 0.0.0.0 --port 8000
```

Kontrol: tarayıcıda `http://localhost:8000/docs` açılırsa sunucu çalışıyor demektir. Bu sayfadan her API'yi deneyebilirsiniz.

### Kullanıcılar ve giriş
İlk çalıştırmada sunucu bir yönetici hesabı oluşturur: **admin / cvsafe123**. İlk girişten sonra bu şifreyi web panelindeki **Users** sayfasından değiştirin.
`CVSAFE_DEMO=1` ile başlatılırsa iki deneme hesabı daha oluşur: **isg / cvsafe123** (İSG uzmanı) ve **saha / cvsafe123** (saha şefi).

| Rol | Yapabildikleri |
| --- | --- |
| Administrator | Her şey: kamera ekleme/silme, kullanıcı yönetimi |
| OHS Specialist | Bölge çizme, taşeron yönetimi, olaylar, raporlar |
| Site Manager | Uyarıları görme ve yanıtlama, AI Scan, istatistikler |

### Kamera bağlama
Web panelinde **Cameras & Zones > Add Camera** ile kamera ekleyin. **Stream source** alanına RTSP adresi yazın:

```
rtsp://kullanici:sifre@192.168.1.21:554/stream1
```

Gerçek kamera yoksa bir video dosyasının yolunu da yazabilirsiniz (`C:/videolar/santiye.mp4`). Dosya döngüyle kamera gibi oynatılır; canlı görüntü ve otomatik uyarılar oluşur.
`config.yaml` artık yalnızca ilk çalıştırmada başlangıç verisi olarak okunur; sonraki değişiklikler panelden yapılır ve veritabanında saklanır.

### Testler
`backend/tests/samples/` klasörüne insan içeren iki fotoğraf koyun: `people.jpg` ve `street.jpg`. Ardından:

```bash
pytest -q tests
```

---

## 2. Flutter uygulamasını çalıştırma

Gereken: Flutter SDK 3.22 veya üstü (`flutter doctor` temiz olmalı).

İlk kurulumda platform klasörlerini (android/ios/web) oluşturup kamera ve ağ izinlerini ekleyen betiği **bir kez** çalıştırın:

```bash
cd mobile
bash setup.sh                                          # macOS / Linux
powershell -ExecutionPolicy Bypass -File setup.ps1     # Windows
```

Sonra:

```bash
flutter run
```

### Uygulamayı sunucuya bağlama
Uygulamada sağ üstteki profil simgesine dokunup sunucu adresini girin:

- **Android emülatörü:** `http://10.0.2.2:8000` (varsayılan)
- **Gerçek telefon:** `http://<bilgisayarın yerel IP'si>:8000`. Telefon ve bilgisayar aynı Wi-Fi ağında olmalı. IP'yi Windows'ta `ipconfig`, macOS/Linux'ta `ifconfig` ile bulabilirsiniz. Windows güvenlik duvarı 8000 portunu sorabilir; izin verin.
- **Web:** `flutter run -d chrome` ve adres `http://localhost:8000`

Sunucuya ulaşırsa giriş ekranı açılır; kullanıcı adı ve şifreyle girin. Sunucuya ulaşamazsa uygulama demo verilerle açılır ve üstte sarı bir uyarı görünür. AI Scan için sunucu bağlantısı şarttır.

### Web panelini çalıştırma
Aynı `mobile` klasöründe, ayrı bir PowerShell penceresinde:

```bash
flutter run -d chrome -t lib/main_panel.dart
```

Giriş ekranında sunucu adresi `http://localhost:8000` olmalı.

| Sayfa | İçerik |
| --- | --- |
| **Dashboard** | Uyum endeksi, açık uyarılar, zaman içinde ihlal grafiği, ihlal türü ve kamera dağılımı, kamera durumu |
| **Incidents** | Tüm olaylar; durum, tür ve kamera filtresi. Satıra tıklayınca kanıt görüntüsü, zaman çizelgesi ve müdahale butonları açılır. |
| **Cameras & Zones** | Kamera ekleme/düzenleme. **Zones** butonuyla kamera görüntüsü üzerine fareyle köşe köşe bölge çizilir. Canlı yayın yoksa bir referans fotoğraf yüklenir. |
| **Subcontractors** | Taşeron firmalar ve sorumlu oldukları kameralar |
| **Reports** | Dönem özeti tabloları ve PDF rapor |
| **Users** | Kullanıcı ekleme, şifre sıfırlama, silme (sadece admin) |

---

## 3. Ekranlar

| Ekran | İçerik |
| --- | --- |
| **Alerts** | Açık uyarılar (5 sn'de bir güncellenir), filtreler (Kritik / KKD / Bölge / Çözülen), "Acknowledged", "False Alarm", siren/anons/uyarı kaydı. Yeni uyarı gelince titreşim ve bildirim bandı çıkar. |
| **Evidence** | Seçili olayın kanıt görüntüsü (işaretli / ham-bulanık), taşeron, bölge, takip numarası, ilgili mevzuat, müdahale butonları ve zaman çizelgesi |
| **AI Scan** | Fotoğraf çek veya galeriden seç, video kaydet veya galeriden seç. Sonuçta kişi bazında baret, yelek ve emniyet kemeri durumu, bölge ihlali, düşme, iş makinesine yakınlık görünür. İsterseniz sonuçlar uyarıya dönüştürülür. |
| **Live CCTV** | Kameraların saniyede bir yenilenen yapay zekâ işaretli görüntüsü, 2x2 grid, bölgelerin listesi (salt okunur), siren |
| **Analytics** | Uyum endeksi, taranan kişi sayısı, ortalama müdahale süresi, KKD oranı, ihlal dağılımı, taşeron sıralaması, PDF rapor |

## 4. Yapay zekâ nasıl çalışıyor

1. **YOLO11-pose** kişileri ve 17 vücut noktasını (baş, omuz, kalça, ayak bileği) bulur.
2. **KKD kontrolü:** `weights/ppe.pt` varsa eğitilmiş KKD modeli kullanılır. Yoksa geçici bir **renk tabanlı yöntem** çalışır: baş üstünde baret renkleri, gövdede fosforlu yelek renkleri aranır.
3. **YOLO11 (COCO)** araç ve kamyonları bulur; işçi araca çok yakınsa uyarı verir.
4. **Kurallar:** yasak bölgeye girme (ayak noktası bölge çokgeninin içinde mi), yüksekte çalışma bölgesinde emniyet kemeri, düşme (gövde eğimi; bacaklar görünüyorsa).
5. **Video ve kamera:** ByteTrack aynı kişiyi kareler boyunca takip eder. Bir ihlal ancak aynı kişide art arda birkaç karede görülürse uyarıya dönüşür. Aynı kişinin tekrarları tek uyarıda birleştirilir.
6. **KVKK:** Kaydedilen ve gönderilen her görüntüde yüzler bulanıklaştırılır.

### Asıl KKD modelini eğitme (önemli)
Renk tabanlı yöntem sadece başlangıç içindir. Baret takmayan ama sarı şapkalı birini baretli sanabilir; emniyet kemerini ise hiç göremez. Projenin hedefi olan %85 mAP için:

1. Roboflow Universe'ten "Construction Site Safety" gibi YOLO formatında bir KKD veri seti indirin. SHWD veri seti de kullanılabilir.
2. `training/data.yaml` içindeki yolu düzenleyin.
3. GPU'lu bir bilgisayarda veya Google Colab'da `python training/train_ppe.py --epochs 80` komutunu çalıştırın.
4. Oluşan `weights/ppe.pt` dosyası sunucu yeniden başlatılınca otomatik kullanılır; `/health` çıktısında `"mode": "ppe-model"` görünür.

Sınıf adları (Hardhat, NO-Hardhat, Safety Vest, harness...) otomatik eşleştirilir.

## 5. Bilinen sınırlar ve sonraki adımlar
- **Bildirimler:** Uygulama açıkken 5 saniyede bir kontrol edip bildirim bandı gösteriyor. Uygulama kapalıyken bildirim için Firebase Cloud Messaging (FCM) eklenmeli.
- **Canlı görüntü:** Saniyede bir yenilenen işaretli kare olarak geliyor. Gerçek video akışı (WebRTC/HLS) web panelinde düşünülebilir.
- **Mevzuat referansları:** yol gösterici niteliktedir; ilgili maddeyi İSG uzmanı teyit etmelidir.
- **İşlem gücü:** CPU'da bir kare yaklaşık 0,2–0,4 sn sürer. GPU veya ONNX/TensorRT dönüşümüyle 4 kamera hedefine ulaşılır.

## 6. API özeti

| Yöntem | Yol | Açıklama |
| --- | --- | --- |
| POST | `/auth/login` | Giriş; dönen `token` diğer isteklerde `Authorization: Bearer <token>` başlığıyla gönderilir |
| GET | `/health` | Model modu, aktif akışlar, gecikme (girişsiz) |
| GET/POST/DELETE | `/users` | Kullanıcı yönetimi (admin) |
| POST/DELETE | `/cameras` | Kamera ekleme/düzenleme/silme (admin) |
| PUT | `/cameras/{id}/zones` | Bölgeleri kaydetme (admin, İSG) |
| POST | `/cameras/{id}/reference` · GET `/cameras/{id}/frame` | Referans fotoğraf yükleme; canlı/referans kare |
| POST/DELETE | `/subcontractors` | Taşeron yönetimi (admin, İSG) |
| GET | `/site` | Şantiye, kameralar, bölgeler, taşeronlar |
| GET | `/incidents?status=open&category=ppe&camera_id=CAM-01&offset=0` | Uyarı listesi (filtreli, sayfalı) |
| GET | `/incidents/{id}` | Uyarı detayı ve zaman çizelgesi |
| POST | `/incidents/{id}/ack` · `/false_alarm` · `/action` | Müdahale kayıtları |
| POST | `/analyze/image` | Fotoğraf analizi (multipart: `file`, `camera_id`, `create_incidents`) |
| POST | `/analyze/video` → GET `/jobs/{id}` | Video analizi (arka planda, ilerleme yüzdesiyle) |
| GET | `/cameras/{id}/snapshot` | Kameranın son işaretli karesi |
| GET | `/analytics?range=today\|week\|month` | Göstergeler |
| GET | `/reports/summary.pdf?range=week` | PDF rapor |
