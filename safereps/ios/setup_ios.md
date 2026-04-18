# iOS Setup Guide for SafeReps

I have updated the project configurations to ensure the app is runnable on a physical iPhone. Since I cannot access the `pod` command in this environment, please follow these final steps locally:

## Final Installation Steps

1.  **Open terminal** and navigate to the project directory:
    ```bash
    cd /Users/xumic/Developer/SafeReps/safereps
    ```

2.  **Pull latest Flutter dependencies**:
    ```bash
    flutter pub get
    ```

3.  **Install CocoaPods**:
    ```bash
    cd ios
    pod install
    cd ..
    ```

4.  **Run the application**:
    - Via VS Code: Press `F5`.
    - Via Terminal: `flutter run` (Ensure your iPhone is connected).

## Important Configuration Notes

- **Bundle Identifier**: I have updated the bundle ID to `com.xumic.safereps`. This should be unique enough for most development profiles. If you encounter a "Bundle Identifier not available" error in Xcode, please change it to something else in the "Signing & Capabilities" tab.
- **Deployment Target**: The project and all plugins are now set to **iOS 13.0**.
- **Permissions**: Camera and Microphone usage descriptions are already included in `Info.plist`.

## Troubleshooting

If you encounter issues with CocoaPods, try a clean install:
```bash
cd ios
rm -rf Pods
rm Podfile.lock
pod install
cd ..
```
