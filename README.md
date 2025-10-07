# RaspberryPi-AirPlay-Installer

Turn any Raspberry Pi (Zero 2 W, 3, 4, 5) into a modern, high-quality AirPlay 2 receiver in just 5 minutes. This project uses a set of robust scripts to automate the entire installation process, making it incredibly easy to revive your old home theater or favorite speakers.

This project was created to simplify the process originally shown in **[this detailed (but long!) manual tutorial video](https://www.youtube.com/watch?v=WeibcfMywXU)**. Now, you can achieve the same result with just one command!



---

### ✨ Features

* **🚀 5-Minute Setup:** Go from a fresh Raspberry Pi OS to a working AirPlay 2 speaker in minutes.
* **🤖 Fully Automated:** The script handles system updates, dependency installation, compiling, and configuration.
* **✅ Smart Pre-Checks:** A pre-installation script verifies your system is ready, checking for internet, disk space, and audio devices to prevent errors.
* **🔌 USB DAC Auto-Detection:** Intelligently finds your external USB sound card and lets you choose the correct one if you have multiple.
* **⚙️ Optimized for Performance:** Automatically configures settings for the best audio quality and disables Wi-Fi power saving to prevent dropouts.
* **🛠️ Robust & Reliable:** Includes error handling and detailed logging for easy troubleshooting.

---

### 硬件要求

* **Raspberry Pi:** A Pi Zero 2 W, 3, 4, or 5 is recommended.
* **MicroSD Card:** A quality card with at least 8GB.
* **Power Supply:** The official power supply for your Pi model.
* **Audio Output:**
    * For Pi Zero: An **OTG cable** and a **USB DAC** with a 3.5mm output.
    * For Pi 3/4/5: The built-in 3.5mm jack or an optional USB DAC.

---

###  Quick Start Installation

After installing Raspberry Pi OS Lite and connecting to your Pi via SSH, run this single command. It will download the pre-check script and, if successful, automatically launch the main installer.

```bash
curl -sSL [https://raw.githubusercontent.com/Techposts/AmbiSense/main/Assets/pre_check_airplay_on_pi.sh](https://raw.githubusercontent.com/Techposts/AmbiSense/main/Assets/pre_check_airplay_on_pi.sh) | bash
```

The script is interactive and will guide you through the following steps:
1.  **System Check:** Verifies your Pi is ready.
2.  **Audio Device Selection:** Lets you choose your connected sound card.
3.  **Naming Your Device:** Asks you to name your new AirPlay speaker.
4.  **Wi-Fi Optimization:** Asks for permission to disable power saving.
5.  **Final Confirmation:** Summarizes your choices before starting.

Once finished, it will reboot, and your AirPlay 2 receiver will be ready to use!

---

### How It Works

This project uses a two-script system for a safe and reliable installation:

1.  **`pre_check_airplay_on_pi.sh`:** A non-invasive script that checks your system for common issues without making any changes. If all checks pass, it automatically downloads and runs the main installer.
2.  **`install_airplay_v3.sh`:** The powerful main installer that performs all the required actions to build and configure the AirPlay 2 software (`Shairport-Sync` and `nqptp`).

---

### License

This project is licensed under the MIT License. See the `LICENSE` file for details.
