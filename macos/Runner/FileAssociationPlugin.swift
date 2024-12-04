import Cocoa
import FlutterMacOS

class FileAssociationPlugin: NSObject, FlutterPlugin {
    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "file_association",
            binaryMessenger: registrar.messenger)
        let instance = FileAssociationPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getInitialFilePath":
            // Return the initial file path if any
            if let initialFilePath = UserDefaults.standard.string(forKey: "InitialFilePath") {
                UserDefaults.standard.removeObject(forKey: "InitialFilePath")
                result(initialFilePath)
            } else {
                result("")
            }
        default:
            result(FlutterMethodNotImplemented)
        }
    }
}