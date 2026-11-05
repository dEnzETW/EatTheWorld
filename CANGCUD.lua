# Audit CN-Kedada — Eat The World (ETW)

**Tanggal pemeriksaan:** 5 November 2026 (WIB)  
**Repo:** https://github.com/CN-Kedada/eat-the-world-script  
**Branch:** `main`  
**Commit ETW Script terbaru yang diperiksa:** `e9bda0854a90b4c23ca95201766da05841ce2439`

> Analisis dilakukan dengan membaca dan membongkar string `string.char(...)` secara statis. Tidak ada script yang dijalankan di Roblox.

## 1. Inventaris file publik

| Path | Ukuran saat diperiksa | Catatan |
|---|---:|---|
| `ETW Script` | 3,481,483 byte | Varian utama; UI Inggris; Auto Farm, Auto Collect, Auto Claim, Auto Eat, map/player utilities |
| `Auto.txt` | 664,238 byte | Varian Auto Farm terpisah; map list, timer 5,410 detik, pindah ke Normal/Mega |
| `ZW` | 3,429,320 byte | Varian UI Mandarin; fungsi inti mirip ETW Script |
| `yny` | 3,755,921 byte | Varian UI Vietnam; Auto Farm, player-grab, Throw, hold-grab, flight |
| `Auto` | 1 byte | Placeholder/kosong |
| `动作包` | 1 byte | Placeholder/kosong |

Keempat file script besar menampilkan wrapper **MoonSec Protection v4.0** dan string atribusi `Hendar Development`. Itu adalah atribusi/branding yang tertanam di protektor; bukan bukti pembuat logika ETW.

Riwayat repo: dibuat 2 Februari 2026. `ETW Script` diperbarui pada 5 November 2026 pukul 20:27 WIB. Dua commit terakhir pada file utama menghasilkan source terurai 4.540 baris yang hanya berbeda pada kapitalisasi satu entri whitelist (`Jxsitapp` menjadi `jxsitapp`). `yny` terakhir diperbarui 2 November 2026; `Auto.txt` 29 Oktober 2026; `ZW` 4 September 2026.

## 2. Dependensi data ETW

Struktur karakter yang dicari oleh Auto Farm:

```text
Character
├── Humanoid
├── HumanoidRootPart
├── Size
├── Events
│   ├── Grab
│   ├── Eat
│   └── Sell
├── CurrentChunk
├── SendTrack
├── Radius
├── LocalChunkManager
└── Animate
```

Upgrade yang dibaca:

```text
LocalPlayer.Upgrades.MaxSize
LocalPlayer.Upgrades.Multiplier
```

Objek dunia yang dipakai untuk visual/map:

```text
workspace.Map
workspace.Chunks
workspace.Loading
workspace.Cube
```

Ini adalah nama instance yang diharapkan source; tetap perlu dicek ulang pada versi game yang sedang berjalan.

## 3. Remote/event yang ditemukan

| Instance/event | Pemakaian dalam source |
|---|---|
| `Character.Events.Grab` | Meminta grab; variasi argumen digunakan untuk grab objek atau player |
| `Character.Events.Eat` | Meminta proses makan |
| `Character.Events.Sell` | Meminta jual ketika `Size` mencapai `MaxSize` |
| `Character.SendTrack` | Dipanggil selama loop farm |
| `Events.SetServerSettings` | Mengirim `{MapTime = -1, Paused = true}` untuk menghentikan/mengakhiri siklus map |
| `Events.RewardEvent` | Klaim timed reward |
| `Events.SpinEvent` | Dipanggil oleh Auto Claim |
| `Events.RequestTeleport` | Pada `Auto.txt`, meminta mode map `Mega` atau `Normal` |
| `Character.Events.Throw` | Hanya ditemukan pada varian `yny` untuk melempar objek yang sedang dipegang |

Remote yang utama untuk loop farm adalah `Grab`, `Eat`, `SendTrack`, dan `Sell`.

## 4. Cara kerja Auto Farm — ETW Script

1. Membuat Part hitam `bedrock`, ukuran `2048 x 10 x 2048`, posisi `(0, -5, 0)`. Permukaan atasnya berada di Y=0.
2. Menyimpan referensi `workspace.Map` dan `workspace.Chunks`, lalu mengeluarkan keduanya dari Workspace dengan `Parent = nil`.
3. Menunggu `Humanoid`, `HumanoidRootPart`, `Size`, `Events`, `CurrentChunk`, `SendTrack`, dan `Radius`.
4. Menonaktifkan `LocalChunkManager` serta `Animate`.
5. Pada `RunService.Heartbeat`, mengatur state Humanoid ke `Physics`, memastikan root tidak anchored, lalu memanggil `Grab`, `Eat`, dan `SendTrack`.
6. Memantau `CurrentChunk.Value` untuk memperbarui penghitung chunk dan timer.
7. Membandingkan `Size.Value` dengan nilai dinamis `LocalPlayer.Upgrades.MaxSize.Value`.
8. Ketika nilai size mencapai maksimum, memanggil `Sell`; sesudah itu mengirim pengaturan map `{MapTime=-1, Paused=true}`.
9. Saat Auto Farm dimatikan, memutus koneksi, mengembalikan Map/Chunks, menghapus bedrock hitam, serta mengaktifkan lagi LocalChunkManager dan Animate.

**Catatan transisi/visual:** kode tidak menghapus seluruh objek makanan satu per satu. Ia menyembunyikan folder `Map` dan `Chunks`, menonaktifkan `LocalChunkManager` dan `Animate`, lalu tetap mengirim remote Grab/Eat/SendTrack. Ini adalah kombinasi yang paling relevan untuk diteliti saat merekonstruksi perilaku transisi makan dan lantai hitam.

### Loop Auto Farm dan Auto Eat berbeda

- Auto Farm memakai Heartbeat dan mengirim tiga remote farm.
- Auto Eat adalah loop terpisah yang mengirim `Grab` dan `Eat` pada setiap `task.wait()`.
- Menyalakan kedua fitur bersama dapat menumpuk permintaan `Grab`/`Eat`.

### Sistem jalan/grid

Opsi `Move Mode` menggerakkan karakter dalam pola grid dengan memakai `Radius` dan jumlah chunk, dalam batas koordinat sekitar 300 stud. Jika batas lintasan terlampaui, source mengirim pengaturan map `Paused=true` dan mengatur ulang penghitung chunk.

## 5. Auto Sell dan titik rawan

Source membaca `MaxSize` secara dinamis, bukan memakai satu angka maksimum yang tetap. Ini membantu menyesuaikan upgrade yang berubah.

Namun, ada beberapa kondisi penting:

- Jika `Size >= MaxSize` ketika timer masih di bawah 8 detik, source memanggil `Sell`.
- Jika timer sudah lebih dari 8 detik, source hanya mengirim `SetServerSettings` dengan `Paused=true`; cabang ini tidak memanggil `Sell`.
- Ketika `grabTimer > 15`, source mengatur `Size.Value = MaxSize.Value` secara lokal. Nilai lokal ini belum tentu diterima server sebagai ukuran sah.
- Pada cabang timeout lebih dari 8 detik, pemanggilan `SetServerSettings` tidak dibatasi debounce; koneksi Heartbeat dapat mengulang permintaan rapat.
- `sellDebounce` baru di-reset saat `Size.Value == 0`. Jika nilai tidak pernah kembali nol atau event Sell gagal, siklus berikutnya dapat tertahan.
- Jika tidak ada chunk, timer melewati 8 detik dan akhirnya dapat memicu kondisi reset karakter setelah timer lebih dari 60 detik.
- Statistik perkiraan menggunakan `Multiplier.Value / 100`; jika nilainya nol atau belum tersedia, pembagian dapat bermasalah.

Kesimpulan: ada deteksi maksimum yang adaptif, tetapi pemicu Sell, pause map, timeout, dan reset karakter tercampur dalam satu state machine. Ini kandidat utama untuk dibenahi bila Auto Sell kadang tidak jalan.

## 6. Peta, lantai hitam, dan Skip Map

### ETW Script utama

- Bedrock Auto Farm: hitam, `2048 x 10 x 2048`, posisi `(0,-5,0)`.
- Hide Map manual: memindahkan `Map` dan `Chunks` ke `Parent=nil`, lalu membuat bedrock abu-abu ukuran `8192 x 2 x 8192` di `(0,0,0)`.
- Create Platform juga membuat platform abu-abu ukuran `8192 x 2 x 8192`.
- Referensi `Map` dan `Chunks` disimpan saat awal script; jika game mengganti instance folder saat pergantian map, referensi yang disimpan dapat menjadi usang.
- Source utama tidak memiliki sistem blacklist map lengkap atau pemeriksaan “tidak ada makanan tersisa” yang berdiri sendiri.

### Auto.txt

File ini punya sistem map terpisah:

- Membaca nama map dari `ReplicatedStorage.ServerSettings.MapName` atau `CurrentMap`.
- Membandingkan nama secara persis dengan daftar 24 map kecil.
- Jika cocok, menunggu 5 detik lalu mengirim `RequestTeleport("Mega")`, kemudian menunggu 10 detik.
- Daftar yang ditemukan: Raven Rock, Glass Houses, Courtyard, Blox City, Jungle, Community Construction, Candy Land, Ninja Temple, Forest Peak, Mini Baseplate, Martian Madness, Chaos Canyon, Zombie Town, Winter Workshop, Crossroads, Castle Playground, Twister, Battle Zone, Christmas Coast, Grid City, Yorick's Resting Place, Headquarters, Haunted Mansion, Snow Land.
- `Studville` dan `Block Town` tidak ada di daftar itu.
- Jika `ServerSettings` tidak menyediakan `MapName` atau `CurrentMap`, fallback mengambil `workspace.Map.Name`. Bila nama folder itu hanya `Map`, pencocokan daftar map kecil tidak akan cocok.
- Ada countdown tetap `5,410` detik (1 jam 30 menit 10 detik); saat habis, source meminta map `Normal`. Ini bukan pengukuran waktu season dari event makan.
- Map checker berjalan terus selama script aktif; tidak dikaitkan langsung dengan toggle Auto Farm.

Jadi, Auto.txt adalah referensi untuk **pindah mode map berdasarkan nama**, bukan deteksi jumlah makanan. Untuk skip Studville/Block Town karena kehabisan objek, daftar dan logikanya belum cukup.

## 7. Grab Player / Teleport / Throw

### ETW Script utama

- `grabForwardObject()` mengirim `Grab:FireServer(false, false, true)`.
- `Teleport Grab` memilih player dari daftar, memanggil grab remote, menunggu 0,2 detik, lalu memindahkan **karakter lokal** ke belakang target. Jarak dihitung dari nilai currency yang dibaca dari beberapa folder/stat.
- Source tidak memverifikasi bahwa target benar-benar sudah ter-grab sebelum teleport.
- `Teleport Throw` pada varian utama yang dibaca justru menggunakan helper grab, bukan `Throw:FireServer()`.
- Fungsi yang diberi nama `grabPlayerNonStop()` hanya mengirim satu remote saat dipicu, lalu membuat koneksi Heartbeat untuk mempertahankan orientasi karakter. Itu bukan spam grab terus-menerus. Koneksi Heartbeat ini tidak disimpan ke variabel global cleanup yang jelas.

### yny

Varian `yny` menambah beberapa pendekatan:

- Player Grab menggunakan `Character.Events.Grab` dengan argumen `false, true, grabPosition, "弯腰抓取"`.
- Posisi grab dihitung sekitar 30 stud ke depan dari `HumanoidRootPart`.
- Salah satu UI mencoba memindahkan karakter lokal ke dekat target melalui Weld sementara (`weldtp`), kemudian memanggil grab.
- `weldtp` menggunakan `teleportDistance = -25`, memilih part yang `IsGrounded()`, membuat Weld sementara, menunggu satu `RunService.Stepped`, lalu menghancurkan Weld.
- `BasePart:IsGrounded()` memang method resmi Roblox yang memeriksa apakah part tersambung ke part yang menahannya. Referensi: https://create.roblox.com/docs/reference/engine/classes/BasePart
- Varian `yny` punya event `Throw:FireServer()`; setelah itu UI memindahkan karakter lokal ke belakang target. Artinya event Throw dipanggil pada karakter lokal, bukan bukti bahwa target player yang dipilih otomatis ikut terlempar.
- `Hold Grab` mengirim `Grab(false,false,true)` saat tombol ditekan, lalu Heartbeat menjaga orientasi root. Bukan loop spam grab setiap frame.
- Varian ini menambah sistem terbang berbasis BodyGyro/BodyVelocity, input W/A/S/D, tombol naik/turun, serta `Character:TranslateBy()` pada Heartbeat.

## 8. Whitelist dan kebutuhan executor

`ETW Script` utama memeriksa username pemain secara persis melalui daftar lokal:

- 179 entri tertulis.
- 150 username unik.
- 29 entri duplikat; `Player2` muncul 21 kali sebagai placeholder.
- Pengguna di luar daftar diberi layar peringatan dan instruksi bergabung ke Discord `discord.gg/kPN2Szg5E`; script kemudian berhenti.

Dependensi executor/lingkungan yang terlihat:

- `Drawing.new("Text")` untuk overlay statistik.
- `CoreGui` dan fallback ke `PlayerGui`.
- `getgenv()`.
- `setclipboard()`.
- `isfile()`, `readfile()`, `writefile()` untuk file favorit emote `FavoritedEmotes.txt`.

Pemeriksaan string terhadap payload Lua yang sudah dibuka tidak menemukan `HttpGet`, `request()`, `loadstring`, `PostAsync`, `GetAsync`, atau webhook. Yang ditemukan adalah operasi file lokal untuk favorit emote dan clipboard Discord. Ini hasil pemindaian statis payload; bukan jaminan keamanan absolut terhadap wrapper proteksi atau perubahan file di masa depan.

## 9. Perbedaan versi — mana yang dipakai untuk apa

| Kebutuhan | Referensi terbaik | Alasan |
|---|---|---|
| Mesin Auto Farm, Size, Sell, Chunk | `ETW Script` | Versi utama dan paling baru; struktur Inggris jelas |
| Lantai hitam + hide Map/Chunks + disable Animate/LocalChunkManager | `ETW Script` atau `yny` | Keduanya memuat pola itu |
| Auto map kecil → Mega | `Auto.txt` | Satu-satunya varian dengan daftar map kecil dan RequestTeleport Mega |
| Player grab dengan posisi maju dan Weld teleport | `yny` | Memuat argumen grab player dan helper `weldtp` |
| Throw remote dan flight | `yny` | Memuat `Events.Throw` dan flight controls |
| UI Mandarin/varian lebih lama | `ZW` | Struktur fitur mirip versi utama, UI Mandarin |

## 10. Loader yang dipublikasikan pihak ketiga

Sebuah posting Telegram ScriptRoblox memuat loader untuk file `ETW Script` di repo tersebut:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/CN-Kedada/eat-the-world-script/refs/heads/main/ETW%20Script"))()
```

Posting tersebut menyebut Auto Farm, Claim Reward, Show Model, dan Eat Alone. Itu adalah posting pihak ketiga, bukan bukti bahwa kanal Telegram tersebut adalah pemilik repo.

## 11. Rekomendasi rekonstruksi ETW

1. Jadikan `ETW Script` basis untuk struktur data, event, Auto Farm, ukuran, dan jual.
2. Pisahkan state machine Auto Farm dari Auto Eat agar Grab/Eat tidak saling menggandakan pemanggilan.
3. Pisahkan kondisi `size penuh`, `tidak ada chunk`, `timeout`, dan `gagal sell`; jangan gunakan satu cabang `timer > 8` untuk semua keadaan.
4. Verifikasi Sell melalui perubahan nilai `Size`/state server, bukan dengan menganggap pengubahan `Size.Value` lokal sudah sah.
5. Jadikan map skip berbasis dua lapis: nama map yang dilarang (mis. Studville/Block Town) dan deteksi tidak ada chunk/objek selama interval yang bisa dikonfigurasi.
6. Reacquire `workspace.Map`, `workspace.Chunks`, Character, dan RemoteEvent setiap pergantian map/respawn; jangan bergantung pada referensi awal yang bisa usang.
7. Ukur runtime sejak Auto Farm benar-benar mulai. Ukur waktu sesi/season dari event mulai makan yang terdeteksi, bukan dari timer umum atau countdown tetap `5,410` detik.
8. Buat cleanup eksplisit untuk seluruh koneksi Heartbeat, InputBegan, dan UI saat toggle dimatikan atau karakter respawn.

## 12. Link sumber

- Repo: https://github.com/CN-Kedada/eat-the-world-script
- ETW Script: https://github.com/CN-Kedada/eat-the-world-script/blob/main/ETW%20Script
- Auto.txt: https://github.com/CN-Kedada/eat-the-world-script/blob/main/Auto.txt
- ZW: https://github.com/CN-Kedada/eat-the-world-script/blob/main/ZW
- yny: https://github.com/CN-Kedada/eat-the-world-script/blob/main/yny
- ETW Script terbaru (commit 5 Nov 2026): https://github.com/CN-Kedada/eat-the-world-script/commit/e9bda0854a90b4c23ca95201766da05841ce2439
- yny terakhir (commit 2 Nov 2026): https://github.com/CN-Kedada/eat-the-world-script/commit/e0094f5d0978d900f888dbf808226df961ecae9f
- Auto.txt terakhir (commit 29 Okt 2026): https://github.com/CN-Kedada/eat-the-world-script/commit/6e78e93f7fdd200816be5fbe29c3229ff50b0bec
- ZW terakhir (commit 4 Sep 2026): https://github.com/CN-Kedada/eat-the-world-script/commit/3d4ce9b806dadf888731c8317a9eda3bfa0b612f

## Addendum — fitur pendamping pada ETW Script utama

- **Auto Collect:** menonaktifkan `PlayerScripts.CubeVis`, menyisir anak langsung `workspace` untuk objek bernama `Cube`, memeriksa `Owner`, lalu memindahkan Cube yang owner-nya pemain lokal atau string kosong ke `HumanoidRootPart`. Saat dimatikan, `CubeVis` diaktifkan kembali.
- **Auto Claim:** setiap satu detik memeriksa `LocalPlayer.TimedRewards`; reward dengan nilai lebih dari nol dikirim ke `Events.RewardEvent`. Script juga memanggil `Events.SpinEvent` pada setiap putaran loop, tidak hanya ketika reward berubah siap.
- **Auto Eat:** loop terpisah yang mengirim `Character.Events.Grab` dan `Eat` selama toggle aktif.
- **No Slip:** pada `RenderStepped`, membaca `Humanoid.MoveDirection`, menghitung kecepatan target dari `WalkSpeed`, lalu memakai `Vector3:Lerp` untuk mengatur velocity karakter.
- **Anti Fall:** pada Heartbeat, jika Y root turun di bawah titik dasar yang dihitung, velocity di-nol-kan dan karakter dipindahkan kembali ke posisi aman.
- **Gravity Lock:** menulis `workspace.Gravity = 99999999` setiap 0,1 detik. Ini perubahan lokal yang agresif dan dapat menimbulkan perilaku fisika tidak wajar.
- **Hide Map:** memindahkan `Map` dan `Chunks` ke luar Workspace; bedrock-nya abu-abu, bukan bedrock hitam Auto Farm.
- **Create Platform:** membuat Part abu-abu `8192 x 2 x 8192` pada origin.
- **View Data:** menghitung perkiraan growth/price untuk MaxSize, Speed, Multiplier, dan EatSpeed; nama fungsi `loadAndRunPlayerDataScript` tidak berarti ia mengunduh script eksternal.
- **Emotes:** daftar animasi disimpan sebagai favorit lokal melalui `FavoritedEmotes.txt` menggunakan `isfile/readfile/writefile`.

Config Auto Farm utama menggunakan folder/instance di `LocalPlayer.PlayerGui` bernama `ChiChiWorldConfig` dengan JSON pada StringValue; bukan menyimpan seluruh konfigurasi ke file disk. Kunci yang terlihat mencakup `autofarm`, `autoCollectingCubes`, `autoClaimRewards`, `farmMoving`, `showMap`, `autoeat`, `keepUnanchor`, `antiFallEnabled`, `slippageEliminationEnabled`, `gravityLockEnabled`, dan `platformEnabled`.

## Addendum — ukuran source setelah dibuka

| File | Payload yang terbaca statis | Baris hasil pemisahan |
|---|---:|---:|
| `ETW Script` | 193,194 karakter | 4,540 |
| `ZW` | 190,309 karakter | 4,383 |
| `yny` | 208,319 karakter | 4,761 |
| `Auto.txt` | 36,511 karakter | 959 |

Angka tersebut adalah ukuran payload hasil ekstraksi string, bukan jumlah baris file terenkripsi mentah.
