# 🛠 GPX Logger

A **lightweight, efficient, and biker-friendly** GPX logging app built with **Flutter**. Designed for **personal use**, this app dynamically logs location data based on movement patterns and exports **.gpx** files with rich metadata.

## ✨ Features

✅ **Smart Logging**  
- Logs based on **speed, distance, and heading changes**.  
- Time-based logging at **high speeds**, distance-based logging at **low speeds**.  
- Captures **sharp turns** for accurate city traffic logs.

✅ **Data Collected per Log Entry**  
- **Latitude, Longitude, Altitude**  
- **Speed & Heading**  
- **Timestamp**  
- **Terrain Mode** (_City, Highway, Off-Road_)

✅ **File Management**  
- Logs stored in **.txt** format for efficiency.  
- **GPX files generated on demand** instead of real-time updates.  
- Rename, delete, and export trips easily.

✅ **Intuitive UI**  
- All controls **within 200px of the bottom** for easy reach with biker gloves.  
- Dialogs and alerts appear as **bottom sheets**.  

✅ **Adaptive Theming**  
- **Dark/Light mode support** with `AdaptiveTheme`.

✅ **Export & Sharing**  
- **GPX files include speed, heading, and terrain mode** inside `<extensions>` tags.  
- Uses `share_plus` for **direct file sharing**.

## 🚀 Tech Stack
- **Flutter** for UI & logic  
- **Geolocator** for GPS tracking  
- **flutter_map** for map rendering  
- **path_provider** for file handling  
- **xml** for GPX file generation  
- **share_plus** for sharing logs  

## 📦 Installation
1. Clone the repo:  
   ```sh
   git clone https://github.com/yourgithubusername/gpx-logger.git
   ```
2. Navigate to the project folder:  
   ```sh
   cd gpx-logger
   ```
3. Install dependencies:  
   ```sh
   flutter pub get
   ```
4. Run the app:  
   ```sh
   flutter run
   ```

## 📂 Folder Structure

```
📦 gpx_logger
 ┣ 📂 lib
 ┃ ┣ 📜 main.dart  # All the code in one place
 ┣ 📂 android & ios
 ┗ 📜 README.md  # This file
```


## 🎯 Future Enhancements
- **Background logging** (optional)
- **Log preview on map** before export
- **More customization options** (intervals, accuracy, etc.)

## 📝 Notes

- **This app is not meant for public distribution.**
- **Built purely for personal GPX logging & tracking.**
- **Further refinements & optimizations may come later.**


---

⚡ Built for **bikers, adventurers, and GPS enthusiasts** who love efficiency over clutter. 🏍️📍

> _"Because good rides deserve good logs."_

