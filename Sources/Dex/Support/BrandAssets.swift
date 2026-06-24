import AppKit
import Foundation

enum BrandAssets {
    static func logoImage() -> NSImage? {
        image(named: "dex-flat-white-icon", extension: "png")
    }

    static func menuBarTemplateImage() -> NSImage? {
        guard let image = image(named: "menu-bar-template", extension: "png") else { return nil }
        image.isTemplate = true
        image.size = NSSize(width: 18, height: 18)
        return image
    }

    private static func image(named name: String, extension ext: String) -> NSImage? {
        let url =
            Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Brand") ??
            Bundle.module.url(forResource: name, withExtension: ext)
        return url.flatMap(NSImage.init(contentsOf:))
    }
}
