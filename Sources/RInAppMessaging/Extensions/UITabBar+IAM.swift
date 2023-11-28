import UIKit

internal extension UITabBar {

    /// Returns UIControl subviews that are supposed to be UITabBarButton instances matching elements in `items`.
    var buttons: [UIControl] {
        let tabBarButtons = subviews
            .compactMap { $0 as? UIControl } // We are looking for instances of UITabBarButton private class
            .sorted { $0.frame.minX < $1.frame.minX } // Ensuring the right order

        guard tabBarButtons.count == items?.count else {
            Logger.debug("Unexpected tab bar items setup: \(tabBarButtons) \(items ?? [])")
            return []
        }

        return tabBarButtons
    }

    /// Returns item instance that corresponds to provided tab bar button
    func item(of button: UIControl) -> UITabBarItem? {
        guard let buttonItemIndex = buttons.firstIndex(where: { $0 === button }) else {
            return nil
        }

        // index safety is ensured in `buttons` implementation
        return items?[buttonItemIndex]
    }
}

public extension UITabBarItem {
    /// identifier should not be empty
    @objc func canHaveTooltip(identifier: String) {
        ViewListener.currentInstance.register(self, identifier: identifier)
    }
}
