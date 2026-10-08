import Foundation

struct InstallError: Error, CustomStringConvertible {
  let description: String
  init(_ description: String) { self.description = description }
}

/// Package conventions, not a separate installer configuration.
struct AppMetadata {
  let product: String
  let name: String
  let identifier: String
  let license: URL?
  let icon: URL?
  let infoPlist: Data
  let linuxDesktopTemplate: String?

  init(package: URL, product: String) throws {
    guard safeFileName(product) else { throw InstallError("Invalid executable product name: \(product)") }
    self.product = product
    let fm = FileManager.default
    let packaging = package.appendingPathComponent("Packaging")
    let plistURL = packaging.appendingPathComponent("Info.plist")
    var plist: [String: Any] = [:]
    if fm.fileExists(atPath: plistURL.path) {
      guard
        let value = try PropertyListSerialization.propertyList(from: Data(contentsOf: plistURL), format: nil)
          as? [String: Any]
      else { throw InstallError("Packaging/Info.plist must contain a dictionary.") }
      plist = value
    }
    name = (plist["CFBundleName"] as? String) ?? product
    identifier = (plist["CFBundleIdentifier"] as? String) ?? "local.\(product)"
    guard safeFileName(name), safeFileName(identifier) else {
      throw InstallError("App name and identifier must be file names without slashes or control characters.")
    }
    plist["CFBundleName"] = name
    plist["CFBundleIdentifier"] = identifier
    plist["CFBundleExecutable"] = product
    plist["CFBundlePackageType"] = "APPL"
    plist["CFBundleVersion"] = plist["CFBundleVersion"] ?? "1"
    plist["CFBundleShortVersionString"] = plist["CFBundleShortVersionString"] ?? "1.0"
    #if os(Linux)
    let linux = packaging.appendingPathComponent("Linux")
    let template = linux.appendingPathComponent("\(identifier).desktop")
    linuxDesktopTemplate =
      fm.fileExists(atPath: template.path) ? try String(contentsOf: template, encoding: .utf8) : nil
    let conventionalIcon = packaging.appendingPathComponent("AppIcon.png")
    let iconURL =
      fm.fileExists(atPath: conventionalIcon.path)
      ? conventionalIcon : linux.appendingPathComponent("\(identifier).png")
    #else
    linuxDesktopTemplate = nil
    let iconURL = packaging.appendingPathComponent("AppIcon.icns")
    #endif
    icon = fm.fileExists(atPath: iconURL.path) ? iconURL : nil
    if icon != nil { plist["CFBundleIconFile"] = "AppIcon" }
    infoPlist = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    let licenseURL = package.appendingPathComponent("LICENSE")
    license = fm.fileExists(atPath: licenseURL.path) ? licenseURL : nil
  }
}

private func safeFileName(_ value: String) -> Bool {
  !value.isEmpty && !value.hasPrefix(".") && !value.hasPrefix("-") && !value.contains("/")
    && !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
}
