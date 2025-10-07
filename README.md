# RaspberryPi-AirPlay-Installer 📻

Turn any Raspberry Pi (Zero 2 W, 3, 4, 5) into a modern, high-quality AirPlay 2 receiver in just 5 minutes. This project uses a set of robust scripts to automate the entire installation process, making it incredibly easy to revive your old home theater or favorite speakers.

> **If you find this project helpful, please consider giving it a ⭐ star on GitHub!** It helps others discover it and shows your appreciation for the work.

The goal of this project was to simplify the manual installation process, making it accessible to everyone.

| The Old, Manual Way (40+ Minutes) | The New, Automated Way (5 Minutes!) |
| :---: | :---: |
| [![Manual AirPlay 2 Pi Setup](https://img.youtube.com/vi/WeibcfMywXU/0.jpg)](https://www.youtube.com/watch?v=WeibcfMywXU) | **[Link to New Video Coming Soon!]** <br> *(Placeholder for your new, shorter video)* |

---

### ✨ Features

* **🚀 5-Minute Setup:** Go from a fresh Raspberry Pi OS to a working AirPlay 2 speaker in minutes.
* **🤖 Fully Automated:** The script handles system updates, dependency installation, compiling, and configuration.
* **✅ Smart Pre-Checks:** A pre-installation script verifies your system is ready, checking for internet, disk space, and audio devices to prevent errors.
* **🔌 USB DAC Auto-Detection:** Intelligently finds your external USB sound card and lets you choose the correct one if you have multiple.
* **⚙️ Optimized for Performance:** Automatically configures settings for the best audio quality and prompts to disable Wi-Fi power saving to prevent dropouts.
* **🛠️ Robust & Reliable:** Includes error handling and detailed logging for easy troubleshooting.

---

### Hardware Requirements

* **Raspberry Pi:** A Pi Zero 2 W, 3, 4, or 5 is recommended.
* **MicroSD Card:** A quality card with at least 8GB.
* **Power Supply:** The official power supply for your Pi model.
* **Audio Output:**
    * For Pi Zero: An **OTG cable** and a **USB DAC** with a 3.5mm output.
    * For Pi 3/4/5: The built-in 3.5mm jack or an optional USB DAC.

---

###  🚀 Quick Start Installation

After installing Raspberry Pi OS Lite and connecting to your Pi via SSH, run this single command. It will download the pre-check script and, if successful, automatically launch the main installer.

```bash
curl -sSL https://raw.githubusercontent.com/Techposts/RaspberryPi-AirPlay-Installer/main/RaspberryPi-AirPlay-Installer-Scripts/pre_check_airplay_on_pi.sh | bash
curl -sSl https://raw.githubusercontent.com/Techposts/RaspberryPi-AirPlay-Installer/main/RaspberryPi-AirPlay-Installer-Scripts/install_airplay_v3.sh | bash
```

The script is interactive and will guide you through the process. Once finished, it will reboot, and your AirPlay 2 receiver will be ready to use!

---

### ✅ The Final Result

When you're done, your setup will be seamless. Your Raspberry Pi will appear as a native AirPlay device on your network, ready to stream from any Apple device.

| Mobile Screenshot | Hardware Setup |
| :---: | :---: |
| **** <br> *Your new device, ready to connect.* | **** <br> *The simple and clean hardware setup.* |

---

### How It Works

This project uses a two-script system for a safe and reliable installation:

1.  **`pre_check_airplay_on_pi.sh`:** A non-invasive script that checks your system for common issues without making any changes. If all checks pass, it automatically downloads and runs the main installer.
2.  **`install_airplay_v3.sh`:** The powerful main installer that performs all the required actions to build and configure the AirPlay 2 software (`Shairport-Sync` and `nqptp`).

---

### ❤️ Support the Project

If this installer helped you bring your old speakers back to life, please consider showing your support!

* **⭐ Star the Repository:** Starring this project on GitHub is a great way to show your appreciation and helps others find it.
* **👍 Like & Subscribe:** If you came from the video tutorial, please **like the video** and **[subscribe to the channel](https://www.youtube.com/@Techposts)**. It helps us create more content like this.

---


### License

This project is licensed under the MIT License. See the `LICENSE` file for details.


