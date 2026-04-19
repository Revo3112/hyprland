# Arsitektur & Panduan Sistem Agentic AI Quickshell
**Direktori Utama**: `~/.config/quickshell/ii/`
**Dokumen ini meringkas keseluruhan anatomi, arsitektur *Agentic AI*, *Function Calling*, integrasi data, hingga mekanisme *UI Rendering* Obrolan.**

---

## 1. Otak Utama AI (`services/Ai.qml`)
Ini adalah pusat dari segala skrip kecerdasan buatan. File ini bertanggung jawab atas:
- Penyusunan *System Prompt* (Termasuk penanaman "Konteks Waktu Saat Ini").
- Menyimpan histori pesan obrolan (Array `messageIDs` & Dictionary `messageByID`).
- Mengeksekusi permintaan API lewat Sub-Process QML (`requester`).
- Melakukan rotasi pengecekan jadwal otonom (*Agentic Heartbeat*).

### Cara Mengatur API Key (Rahasia)
API Key **TIDAK** didaftarkan di dalam *hard-code* QML demi keamanan. Alurnya adalah:
1. User memasukkan API key dari menu GUI Settings (App Setting Quickshell `quickshell -c ii-settings`).
2. Disimpan ke sistem KDE/GNOME Keyring Linux (menggunakan `secret-tool` via `KeyringStorage.qml`).
3. Di `Ai.qml`, key ini dipanggil dan dilempar ke *environment variable* Bash (`export OPENAI_API_KEY="..."`) sebelum `curl` dieksekusi.

### Cara Mengganti/Menambah API URL (LLM Provider)
Untuk menambah provider baru seperti *Gemini, Claude, Groq, dll*, kamu harus mengedit **Api Strategies**:
- Direktori: `services/ai/OpenAiApiStrategy.qml` atau `MistralApiStrategy.qml`.
- File strategy ini mendefinisikan *Endpoint URL*, *Auth Header*, serta bagaimana *JSON Response* dari LLM dibongkar (parsing logik) termasuk proses pengambilan *Stream* data (SSE).

---

## 2. Cara Menambahkan *Tools* / Kemampuan Baru ke AI
Teknologi yang digunakan adalah **Function Calling** (AI memanggil fungsi lokal di komputermu).
Bila kamu ingin mengajari AI cara mengontrol komputermu, ikuti 3 langkah ini di `Ai.qml`:

1. **Daftarkan Fitur di Array Tools JSON**
   Cari properti `property var tools: ({ "openai": { "functions": [ ... ] } })` di `Ai.qml`.
   Tambahkan skema JSON fungsi baru, contoh:
   ```json
   {
       "type": "function",
       "function": {
           "name": "matikan_lampu_kamar",
           "description": "Mematikan lampu smart home di kamar."
       }
   }
   ```
2. **Eksekusi Aksi di `handleFunctionCall`**
   Cari fungsi `function handleFunctionCall(name, args, item)`. Buat blok `if-else` baru.
   ```javascript
   } else if (name === "matikan_lampu_kamar") {
       Quickshell.execDetached(["bash", "-c", "curl http://lampukamar/off"]); // Eksekusi bash
       addFunctionOutputMessage(name, "Lampu sukses dimatikan"); // Lapor balik ke AI
       requester.makeRequest(); // Beri tahu AI untuk melanjutkan chatnya
   }
   ```

---

## 3. Sistem Pergerakan Otonom (Agentic Heartbeat)
Sistem AI klasik hanya membalas saat kamu *chat*. Sistem kita sekarang **"Hidup Sendiri"**.
Ini dikendalikan oleh **`proactiveTimer`** di `Ai.qml`.

- **Interval**: 30.000 ms (30 Detik)
- **Cara Kerja**: 
  Setiap 30 detik, AI membandingkan jam saat ini dengan data di `GCal.events` (Jadwal Rapat) dan `Todo.list` (Tugas Deadline).
- **Eksekusi Native**: Jika ada yang akan berdering (misal 5 menit lagi), AI mengeksekusi Pop-up Warning merah (`notify-send -u critical ...`).
- **Injeksi Chat Gaib (`sendHiddenPrompt`)**: AI juga me- *rekayasa* pesan *User* kasat mata (Hidden) ke dalam otak LLM yang isinya: *"Secara otonom, sapa aku dan ingatkan ada meeting 5 menit lagi"*. Ini memaksa AI mengirim balon percakapan otonom secara *real-time*, lengkap dengan *link Google Meet* bila ada!

---

## 4. Google Calendar (`gcal-fetcher.py`)
- Python Script (`services/gcal/gcal-fetcher.py`) ini adalah penghubung OAuth 2.0 dengan server Google.
- Mendukung argumen: `--days 60`, `--refresh`, `--create`, `--delete`, `--update-id`. 
- **Bug Kritis "Blindness" (Selesai Diperbaiki)**: Sebelumnya AI menggunakan argumen Google Parameter `timeMin = waktu sekarang`. Efeknya: AI menjadi "Buta" kepada semua jadwal yang *sudah berakhir* di hari itu. Jika ada meeting jam 8 Pagi dan kamu menyuruh AI menghapusnya di jam 9 Malam, AI bilang *"Tidak ada meeting"*. Ini telah ditambal dengan mengunci `timeMin` ke jam `00:00:00` (*Midnight*) hari lokal.

---

## 5. Google Workspace Gmail (`gmail-fetcher.py`)
- Python Script (`services/gmail/gmail-fetcher.py`) ini adalah penghubung OAuth 2.0 dengan server Gmail API.
- Mendukung pemanggilan fungsional tingkat tinggi seperti baca, balas, dan kirim email, serta modifikasi label (Trash, Unread, dsb).
- Menghindari limitasi ukuran konteks token LLM dengan membungkus keseluruhan 81 fungsi endpoint dari dokumentasi REST API Gmail ke dalam parameter *Raw API Call Passage (`--raw-api`)*. Model hanya memanggil argumen `resource` (format berantai object notation tanpa *parentheses*), `method`, dan sekumpulan `kwargs`.
- Semua proses keluaran dieksekusi dan dijembatani secara asinkron (QML `StdioCollector`) dari terminal Python ke dalam eksekutor argumen `handleFunctionCall`.

---

## 6. Local Todo List Canggih
- Disimpan dalam bentuk JSON murni offline (`todo.json`).
- Mendukung fitur tenggat waktu (`dueDate`) bersertifikat *ISO 8601*.
- **Peningkatan UX Manual Widget Todo**:
  Tombol `+` (Manual Add Task) di Widget Quickshell telah dipercanggih di `TodoWidget.qml`. Daripada mengetik `2026-03-24 15:00` kaku, user bisa mengetik bahasa sehari-hari:
  - `"besok"`
  - `"nanti"`
  - `"lusa"`
  - `"18:30"`
  Semuanya akan ditangkap oleh *JavaScript RegEx Parser* ringan buatan kita lalu diselaraskan langsung ke sistem alarm Otonom 30-detik kita.

---

## 7. Panduan: Cara Menambahkan Model AI Baru (LLM Lain)
Bagi *developer* masa depan (atau AI lain) yang ingin menambahkan model/layanan LLM baru (misalnya Claude, Groq, Llama, Ollama Lokal, dll) ke dalam Quickshell, perhatikan langkah-langkah mutlak ini:

1. **Mendefinisikan *Model Object* di `Ai.qml`**
   Buka file `services/Ai.qml` dan cari *Dictionary* `property var models: ({...})`. Kamu harus mendaftarkan model barunya dengan skema berikut:
   ```json
   "nama_model_bebas": {
       "name": "Groq-Llama-3",           // Nama yang tampil di Switcher UI
       "model_string": "llama3-70b",     // ID Model Asli API
       "api_format": "openai",           // Format API Strategy yg akan dipakai (Misal: openai atau mistral)
       "requires_key": true,             // Butuh API Key?
       "key_id": "groq",                 // Identifier key di Keyring KDE
       "supports_vision": false          // Apakah mendukung baca gambar?
   }
   ```
2. **Memahami *API Strategy Format***
   Property `"api_format": "openai"` di atas sangatlah vital! Kata `"openai"` ini merujuk ke QML Component Strategy `OpenAiApiStrategy.qml`. Ini berarti model Groq-Llama-3 kamu akan **membonceng** logika format API dan *Standard Server-Sent Events (SSE)* milik OpenAI. Kalau AI baru yang ingin kamu tambahkan punya format parsing/struktur JSON payload yang berbeda dari OpenAI/Mistral, kamu WAJIB membuat file QML *Strategy* baru (contoh: `AnthropicApiStrategy.qml`) dan mendaftarkannya di folder `services/ai/`.

---

## 8. Arsitektur Tampilan Obrolan & Parser UI (Chat UI)
Sistem tampilan percakapan telah dimodifikasi menyerupai platform AI profesional (seperti *Claude/Gemini*) dengan mekanisme konsolidasi balon obrolan secara cerdas. File-file vital yang mengontrol tampilan ini meliputi:

- **`qs.modules.common.functions` (`StringUtils.qml`)**: 
  Di sinilah letak jantung *Markdown Parser* (Fungsi `splitMarkdownBlocks`). Fungsi ini merobek-robek output teks AI. Kemampuannya yang paling mutakhir adalah algoritma **Penggabungan "Thought" Beruntun**. Jika AI (*Mistral/GLM-5*) memuntahkan banyak blok `<think>...</think>` secara berturut-turut untuk setiap tahap berpikir, fungsi ini akan menyedot semuanya menjadi satu kesatuan balok panjang dan memformatnya secara otomatis menggunakan penomoran (*1., 2., 3., dst*).
- **`AiChatMessage.qml` & `MessageThinkBlock.qml`**:
  Komponen visual obrolan. `MessageThinkBlock` dirancang khusus untuk mewadahi data *Thought* tadi. Jika ia mendeteksi adanya penggabungan tahap berpikir di satu pesan, ia akan mengganti judulnya secara dinamis menjadi: **"Thought · N langkah"** atau **"Thinking · N langkah"**.
- **`Ai.qml` (Manipulasi Balon Otonom)**:
  Terdapat dua *Memory Pointers* yang bekerja bersamaan tapi tidak saling tumpang tindih:
  - `rawContent` (Murni untuk Payload/Sejarah API ke server LLM. Tidak boleh kotor).
  - `content` (Murni untuk layang GUI pengguna).
  Saat AI berteriak meminta eksekusi tool, UI di layar akan **menyembunyikan** *Assistant bubble* lama (`visibleToUser = false`), lalu mewariskannya secara visual ke balon baru bersama dengan jejak eksekusi tool tersebut (di bawah naungan blok tataletak Markdown ` ``` `). Sehingga visual di mata *User* adalah SATU proses berjalan (*Thought -> Tool Output -> Jawaban*), padahal API melihatnya sebagai percakapan turn-based normal!

---

## 9. Daftar File Wajib Baca (Sistem Anatomi Inti AI)
Jika ada agen AI lain yang hendak membongkar atau melanjutkan modifikasi sistem ini, mereka **WAJIB** membaca dan meresapi struktur file berikut untuk tidak merusak *logic flow*:

1. **`~/.config/quickshell/ii/services/Ai.qml`** 🧠
   - Otak Utama seluruh sistem. Di sinilah letak *Timer Otonom* (Loop baca Todo/Calendar), Pendelegasian Skrip (*Requester Process*), Konteks Tanggal-Waktu *System Prompt*, Skema JSON untuk *Tools Function-Calling*, dan penanganan respons balik API di `handleFunctionCall()`.
2. **`~/.config/quickshell/ii/services/ai/OpenAiApiStrategy.qml` (atau `MistralApiStrategy.qml`)** 📡
   - Ini bukan sekadar file pendukung; file ini bertugas merakit URL Endpoint LLM, merakit JSON Header (*Bearer Auth*), dan membongkar (`JSON.parse`) potongan respon teks *streaming* SSE karakter demi karakter sebelum disodorkan ke layar user atau dieksekusi sebagai *Function Calling*.
3. **`~/.config/quickshell/ii/services/gcal/gcal-fetcher.py` & `~/.config/quickshell/ii/services/gmail/gmail-fetcher.py`** 🗓️ 📧
   - Skrip Python inti untuk integrasi kalender dan kotak masuk Google. Perhatikan baik-baik log parameter seperti *timezone* untuk kalender, serta pola tangkapan *Raw API Call passage* untuk mengeksekusi ke-81 perintah *REST endpoint* Gmail tanpa kelebihan batas token LLM.
4. **`~/.config/quickshell/ii/services/Todo.qml` & `~/.config/quickshell/ii/modules/ii/sidebarRight/todo/TodoWidget.qml`** ☑️
   - Basis data JSON offline untuk *Task Management*. Berisi parameter tanggal absolut ISO `dueDate` dan parser NLP (*Natural Language*) JavaScript manual (untuk kata kunci `"besok"`, `"lusa"`, dll).
5. **`~/.config/illogical-impulse/config.json`** ⚙️
   - Otak konfigurasi pusat Quickshell. Modul AI mengambil identitas profil API Key dan pengaktifan/penonaktifan modul otonom dari file preferensi ini.
