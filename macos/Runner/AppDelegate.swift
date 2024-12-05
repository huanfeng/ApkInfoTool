import AppKit
import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
    override func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        return true
    }

    override func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = mainFlutterWindow?.contentViewController as! FlutterViewController
        let registrar = controller.engine.registrar(forPlugin: "FileAssociationPlugin")
        // print("AppDelegate::applicationDidFinishLaunching")

        FileAssociationPlugin.register(with: registrar)
        super.applicationDidFinishLaunching(notification)
    }

    func sendFileToFlutter(filePath: String) -> Bool {
        if let controller = mainFlutterWindow?.contentViewController as? FlutterViewController {
            let channel = FlutterMethodChannel(
                name: "file_association",
                binaryMessenger: controller.engine.binaryMessenger
            )
            channel.invokeMethod("fileOpened", arguments: filePath)
            return true
        }
        return false
    }

    override func application(_: NSApplication, openFile filename: String) -> Bool {
        print("AppDelegate::application: " + filename)
        if !sendFileToFlutter(filePath: filename) {
            // 当 Flutter 还未准备好时，将文件路径存储起来
            UserDefaults.standard.set(filename, forKey: "InitialFilePath")
        }
        return true
    }

    override func application(_: NSApplication, open url: [URL]) {
        print("AppDelegate::application: open: " + url[0].path)
        let _ = sendFileToFlutter(filePath: url[0].path)
    }

    override func application(_: Any, openFileWithoutUI _: String) -> Bool {
        print("AppDelegate::application: openFileWithoutUI")
        return false
    }

    override func application(_: NSApplication, openTempFile _: String) -> Bool {
        print("AppDelegate::application: openTempFile")
        return false
    }

    override func application(_: NSApplication, openFiles files: [String]) {
        print("AppDelegate::application: openFiles:" + files[0])
        let _ = sendFileToFlutter(filePath: files[0])
    }

    override func applicationShouldOpenUntitledFile(_: NSApplication) -> Bool {
        print("AppDelegate::application: applicationShouldOpenUntitledFile")
        return false
    }

    override func applicationOpenUntitledFile(_: NSApplication) -> Bool {
        print("AppDelegate::application: applicationOpenUntitledFile")
        return false
    }
}
