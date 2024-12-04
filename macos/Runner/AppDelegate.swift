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

    override func application(_: NSApplication, openFile filename: String) -> Bool {
        // print("AppDelegate::application: " + filename)

        if let controller = mainFlutterWindow?.contentViewController as? FlutterViewController {
            let channel = FlutterMethodChannel(
                name: "file_association",
                binaryMessenger: controller.engine.binaryMessenger
            )
            channel.invokeMethod("fileOpened", arguments: filename)
            return true
        }
        // 当 Flutter 还未准备好时，将文件路径存储起来
        UserDefaults.standard.set(filename, forKey: "InitialFilePath")
        return true
    }
}
